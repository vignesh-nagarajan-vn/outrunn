//
//  Store.swift
//  outrunn
//
//  On-device state. `AppData` is everything that is saved and is written to
//  disk as is. The ages are never saved: they are recomputed by `AgeEngine`.
//

import Foundation
import Observation

struct AppData: Codable {
    var profile: Profile?
    var scans: [Scan] = []
    var readings: [AgeReading] = []
    var healthEnabled = false
    var health: HealthSnapshot?
    var plan: CoachPlan?
    var chartRange: ChartTimeRange = .day
    var questionsAsked = 0
    var questionsDay = Date.distantPast
}

@Observable
final class Store {
    private(set) var data: AppData
    private(set) var estimate: AgeEstimate?
    private(set) var healthStatus: String?

    private let fileURL: URL?

    /// Pass `fileURL: nil` for a store that lives in memory only.
    init(data: AppData? = nil, fileURL: URL? = Store.defaultFileURL) {
        let initial = data ?? fileURL.flatMap { Store.load(from: $0) } ?? AppData()
        self.fileURL = fileURL
        self.data = initial
        estimate = Store.computeEstimate(for: initial)
    }

    var age: Double {
        data.profile?.age ?? 0
    }

    var latestScan: Scan? {
        data.scans.max { $0.capturedAt < $1.capturedAt }
    }

    var hasWeekOfReadings: Bool {
        guard let first = data.readings.map(\.date).min(),
              let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)
        else { return false }
        return first <= weekAgo
    }

    // MARK: Profile and scans

    func saveProfile(name: String, age: Double) {
        data.profile = Profile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            age: min(90, max(18, age))
        )
        commit()
    }

    func addScan(_ scan: Scan) {
        data.scans.append(scan)
        commit()
        if let estimate {
            data.readings.append(
                AgeReading(
                    date: scan.capturedAt,
                    chronological: age,
                    biological: estimate.biological,
                    cardiac: estimate.cardiac,
                    pulmonary: estimate.pulmonary
                )
            )
            save()
        }
    }

    func setPlan(_ plan: CoachPlan?) {
        data.plan = plan
        save()
    }

    func setChartRange(_ range: ChartTimeRange) {
        data.chartRange = range
        save()
    }

    func reset(_ scope: DataResetScope) {
        if let cutoff = scope.cutoff {
            data.scans.removeAll { $0.capturedAt >= cutoff }
            data.readings.removeAll { $0.date >= cutoff }
        } else {
            data.scans = []
            data.readings = []
            data.chartRange = .day
        }
        data.plan = nil
        commit()
    }

    // MARK: Apple Health

    func enableHealth() async {
        guard HealthService.isAvailable else {
            healthStatus = "Apple Health is not available on this device."
            return
        }
        guard await HealthService.requestAccess() else {
            healthStatus = "Apple Health access was not granted."
            return
        }
        data.healthEnabled = true
        commit()
        await refreshHealth()
    }

    func disableHealth() {
        data.healthEnabled = false
        data.health = nil
        healthStatus = nil
        commit()
    }

    /// Reads Apple Health again when the toggle is on. Does nothing when it is off.
    func refreshHealth() async {
        guard data.healthEnabled else { return }
        let snapshot = await HealthService.fetchSnapshot()
        guard data.healthEnabled else { return }
        data.health = snapshot
        healthStatus = snapshot == nil
            ? "No Apple Health data could be read. Check outrunn's access in the Health app."
            : nil
        commit()
    }

    // MARK: Roadrunner question count

    func questionsRemaining(limit: Int) -> Int {
        let used = Calendar.current.isDateInToday(data.questionsDay) ? data.questionsAsked : 0
        return max(0, limit - used)
    }

    func countQuestion() {
        if !Calendar.current.isDateInToday(data.questionsDay) {
            data.questionsDay = .now
            data.questionsAsked = 0
        }
        data.questionsAsked += 1
        save()
    }

    // MARK: Persistence

    private func commit() {
        estimate = Store.computeEstimate(for: data)
        save()
    }

    private static func computeEstimate(for data: AppData) -> AgeEstimate? {
        guard let profile = data.profile else { return nil }
        return AgeEngine.estimate(
            AgeEngine.Input(chronologicalAge: profile.age, scans: data.scans, health: data.health)
        )
    }

    private func save() {
        guard let fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(data).write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("outrunn save failed: \(error)")
        }
    }

    private static func load(from fileURL: URL) -> AppData? {
        guard let raw = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(AppData.self, from: raw)
        } catch {
            print("outrunn load failed: \(error)")
            return nil
        }
    }

    static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("outrunn", isDirectory: true)
            .appendingPathComponent("store.json")
    }

    #if DEBUG
    static var preview: Store {
        var data = AppData()
        data.profile = Profile(name: "Alex", age: 30)
        data.health = HealthSnapshot(sleepHours: 7.4, stepCount: 8_420, restingHeartRate: 54, hrvSDNN: 61)
        let store = Store(data: data, fileURL: nil)
        store.addScan(
            Scan(
                minutesSinceWorkout: 45,
                heartRate: 64,
                respiratoryRate: 13.2,
                pulseConfidence: 88,
                heartRateRecovery: 28,
                rmssd: 42,
                stressIndex: 92
            )
        )
        return store
    }
    #endif
}
