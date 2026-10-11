//
//  HealthKitManager.swift
//  outrunn
//

import Foundation
import HealthKit
import Observation

struct HealthKitVitals: Hashable {
    var restingHeartRate: Int
    var hrvSDNN: Int
    var sleepScore: Int
    var sleepHours: Double
    var stepCount: Int
    var respiratoryRate: Double
    var activeEnergyBurned: Double
    var peakHeartRate: Int

    func asHealthContext() -> HealthContext {
        HealthContext(
            capturedAt: .now,
            sleepScore: sleepScore,
            sleepHours: sleepHours,
            stepCount: stepCount,
            restingHeartRate: restingHeartRate,
            hrvSDNN: hrvSDNN,
            respiratoryRate: respiratoryRate,
            activeEnergyBurned: activeEnergyBurned,
            peakHeartRate: peakHeartRate
        )
    }
}

@Observable
@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()

    let store = HKHealthStore()
    var statusMessage: String?

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
            HKQuantityType(.stepCount),
            HKCategoryType(.sleepAnalysis)
        ]
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard isHealthDataAvailable else {
            statusMessage = "Health data is unavailable on this device."
            completion(false)
            return
        }

        store.requestAuthorization(toShare: [], read: readTypes) { success, error in
            Task { @MainActor in
                if let error {
                    self.statusMessage = error.localizedDescription
                    completion(false)
                    return
                }
                self.statusMessage = success
                    ? "Apple Health connected."
                    : "Health authorization was not granted."
                completion(success)
            }
        }
    }

    /// 7-day Apple Health baseline plus recent peak HR for HRR cross-reference.
    func fetchLatestVitals() async -> HealthKitVitals? {
        guard isHealthDataAvailable else {
            statusMessage = "Simulator or this device has no HealthKit store."
            return nil
        }

        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let threeHoursAgo = Calendar.current.date(byAdding: .hour, value: -3, to: .now) ?? .now
        let bpm = HKUnit.count().unitDivided(by: .minute())

        async let hrv = statistic(.heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), start: weekAgo, options: .discreteAverage)
        async let rhr = statistic(.restingHeartRate, unit: bpm, start: weekAgo, options: .discreteAverage)
        async let resp = statistic(.respiratoryRate, unit: bpm, start: weekAgo, options: .discreteAverage)
        async let energy = statistic(.activeEnergyBurned, unit: .kilocalorie(), start: Calendar.current.startOfDay(for: .now), options: .cumulativeSum)
        async let sleep = latestSleep()
        async let peak = statistic(.heartRate, unit: bpm, start: threeHoursAgo, options: .discreteMax)
        async let steps = statistic(
            .stepCount,
            unit: .count(),
            start: Calendar.current.startOfDay(for: .now),
            options: .cumulativeSum
        )

        let hrvValue = await hrv
        let rhrValue = await rhr
        let respValue = await resp
        let energyValue = await energy
        let sleepInfo = await sleep
        let peakValue = await peak
        let stepValue = await steps

        let hasAnySample = [hrvValue, rhrValue, respValue, energyValue, sleepInfo?.hours, peakValue, stepValue].contains { $0 != nil }
        guard hasAnySample else {
            statusMessage = "No Apple Health samples yet. Open Apple Health, then turn the toggle on again."
            return nil
        }

        statusMessage = "Apple Health sleep, steps, and vitals loaded."
        let sleepHours = sleepInfo?.hours ?? 0
        let sleepScore = sleepInfo?.score ?? Int(min(100, (sleepHours / 8.0) * 100).rounded())
        return HealthKitVitals(
            restingHeartRate: Int((rhrValue ?? 56).rounded()),
            hrvSDNN: Int((hrvValue ?? 50).rounded()),
            sleepScore: sleepScore,
            sleepHours: sleepHours,
            stepCount: Int((stepValue ?? 0).rounded()),
            respiratoryRate: respValue ?? 14,
            activeEnergyBurned: energyValue ?? 0,
            peakHeartRate: Int((peakValue ?? 0).rounded())
        )
    }

    private func statistic(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        options: HKStatisticsOptions
    ) async -> Double? {
        let type = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, stats, _ in
                let quantity = stats?.averageQuantity() ?? stats?.sumQuantity() ?? stats?.maximumQuantity()
                continuation.resume(returning: quantity?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func latestSleep() async -> (hours: Double, score: Int)? {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let asleepSeconds = (samples as? [HKCategorySample] ?? []).reduce(0.0) { total, sample in
                    guard isAsleepCategory(sample.value) else { return total }
                    return total + sample.endDate.timeIntervalSince(sample.startDate)
                }
                guard asleepSeconds > 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                let hours = asleepSeconds / 3600
                let score = Int(min(100, (hours / 8.0) * 100).rounded())
                continuation.resume(returning: (hours, score))
            }
            store.execute(query)
        }
    }
}

private func isAsleepCategory(_ value: Int) -> Bool {
    let asleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue
    ]
    return asleepValues.contains(value)
}
