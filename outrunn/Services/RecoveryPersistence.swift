//
//  RecoveryPersistence.swift
//  outrunn
//

import Foundation

struct RecoverySnapshot: Codable {
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
}

enum RecoveryPersistence {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func save(_ snapshot: RecoverySnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("outrunn persistence save failed: \(error)")
        }
    }

    static func load() -> RecoverySnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(RecoverySnapshot.self, from: data)
        } catch {
            print("outrunn persistence load failed: \(error)")
            return nil
        }
    }

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = folder.appendingPathComponent("outrunn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("recovery.json")
    }
}
