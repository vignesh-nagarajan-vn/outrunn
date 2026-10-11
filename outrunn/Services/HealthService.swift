//
//  HealthService.swift
//  outrunn
//
//  Read-only Apple Health access. Returns only what Health actually has.
//

import Foundation
import HealthKit

enum HealthService {
    private static let store = HKHealthStore()

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private static var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRate),
            HKQuantityType(.stepCount),
            HKCategoryType(.sleepAnalysis)
        ]
    }

    /// True when the permission sheet completed. iOS does not reveal whether
    /// read access was granted, so an empty snapshot is the only sign it was not.
    static func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            return false
        }
    }

    /// Nil when Health is unavailable or has none of the samples outrunn reads.
    static func fetchSnapshot() async -> HealthSnapshot? {
        guard isAvailable else { return nil }

        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        let peakStart = calendar.date(byAdding: .minute, value: -AgeEngine.peakWindowMinutes, to: .now) ?? .now
        let bpm = HKUnit.count().unitDivided(by: .minute())

        async let hrv = statistic(.heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), start: weekAgo, options: .discreteAverage)
        async let rhr = statistic(.restingHeartRate, unit: bpm, start: weekAgo, options: .discreteAverage)
        async let peak = statistic(.heartRate, unit: bpm, start: peakStart, options: .discreteMax)
        async let steps = statistic(.stepCount, unit: .count(), start: calendar.startOfDay(for: .now), options: .cumulativeSum)
        async let sleep = sleepHours()

        let hrvValue = await hrv
        let rhrValue = await rhr
        let peakValue = await peak
        let stepValue = await steps
        let sleepValue = await sleep

        let snapshot = HealthSnapshot(
            sleepHours: sleepValue,
            stepCount: stepValue.map { Int($0.rounded()) },
            restingHeartRate: rhrValue.map { Int($0.rounded()) },
            hrvSDNN: hrvValue,
            peakHeartRate: peakValue.map { Int($0.rounded()) }
        )
        return snapshot.isEmpty ? nil : snapshot
    }

    private static func statistic(
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

    /// Asleep time over the last 24 hours, or nil when Health has no sleep samples.
    private static func sleepHours() async -> Double? {
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let asleepSeconds = (samples as? [HKCategorySample] ?? []).reduce(0.0) { total, sample in
                    guard isAsleep(sample.value) else { return total }
                    return total + sample.endDate.timeIntervalSince(sample.startDate)
                }
                continuation.resume(returning: asleepSeconds > 0 ? asleepSeconds / 3600 : nil)
            }
            store.execute(query)
        }
    }
}

nonisolated private func isAsleep(_ value: Int) -> Bool {
    let asleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue
    ]
    return asleepValues.contains(value)
}
