//
//  AgeEngineTests.swift
//  outrunnTests
//

import XCTest
@testable import outrunn

final class AgeEngineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// A scan `index` hours after the first one.
    private func scan(_ index: Int = 0, breathing: Double = 14, recovery: Int? = nil) -> Scan {
        Scan(
            capturedAt: start.addingTimeInterval(Double(index) * 3_600),
            minutesSinceWorkout: 30,
            heartRate: 70,
            respiratoryRate: breathing,
            pulseConfidence: 90,
            heartRateRecovery: recovery
        )
    }

    private func estimate(age: Double = 30, scans: [Scan], health: HealthSnapshot? = nil) -> AgeEstimate? {
        AgeEngine.estimate(AgeEngine.Input(chronologicalAge: age, scans: scans, health: health))
    }

    // MARK: No data

    func testNoScansGivesNoEstimate() {
        XCTAssertNil(estimate(scans: []))
        XCTAssertNil(estimate(scans: [], health: HealthSnapshot(sleepHours: 8, stepCount: 9_000, hrvSDNN: 60)))
    }

    // MARK: Missing Health data

    func testWithoutHealthOnlyBreathingCounts() throws {
        let result = try XCTUnwrap(estimate(scans: [scan(breathing: 20)]))

        // (20 - 14) * 0.8 = 4.8 years on the lungs, 30% of that on biological age.
        XCTAssertEqual(result.pulmonary, 34.8, accuracy: 0.001)
        XCTAssertEqual(result.biological, 31.4, accuracy: 0.001)
        XCTAssertNil(result.cardiac)
        XCTAssertEqual(result.factors.map(\.kind), [.breathingRate])
    }

    func testBaselineScanWithoutHealthMatchesChronologicalAge() throws {
        let result = try XCTUnwrap(estimate(scans: [scan(breathing: 14)]))

        XCTAssertEqual(result.biological, 30, accuracy: 0.001)
        XCTAssertEqual(result.pulmonary, 30, accuracy: 0.001)
    }

    func testPartialHealthOnlyAddsWhatWasMeasured() throws {
        let health = HealthSnapshot(stepCount: 6_000)
        let result = try XCTUnwrap(estimate(scans: [scan()], health: health))

        // (8000 - 6000) / 4000 * 0.55 = 0.275 years, rounded to one decimal.
        XCTAssertEqual(result.factors.map(\.kind), [.breathingRate, .steps])
        XCTAssertEqual(result.biological, 30.3, accuracy: 0.001)
        XCTAssertNil(result.cardiac)
    }

    // MARK: Missing heart rate recovery

    func testCardiacAgeIsAbsentWithoutRecoveryOrHRV() throws {
        let health = HealthSnapshot(sleepHours: 7.5, stepCount: 8_000, restingHeartRate: 55)
        let result = try XCTUnwrap(estimate(scans: [scan()], health: health))

        XCTAssertNil(result.cardiac)
        XCTAssertFalse(result.factors.contains { $0.kind == .heartRateRecovery })
        XCTAssertFalse(result.factors.contains { $0.kind == .heartRateVariability })
    }

    func testCardiacAgeFromHRVAloneWhenRecoveryIsMissing() throws {
        let result = try XCTUnwrap(estimate(scans: [scan()], health: HealthSnapshot(hrvSDNN: 45)))

        // (55 - 45) * 0.1 = 1 year on the heart, half of that on biological age.
        XCTAssertEqual(try XCTUnwrap(result.cardiac), 31.0, accuracy: 0.001)
        XCTAssertEqual(result.biological, 30.5, accuracy: 0.001)
        XCTAssertFalse(result.factors.contains { $0.kind == .heartRateRecovery })
    }

    func testCardiacAgeFromRecovery() throws {
        let result = try XCTUnwrap(estimate(scans: [scan(recovery: 20)]))

        // Expected recovery at 30 is 28 beats. (28 - 20) * 0.4 = 3.2 years.
        XCTAssertEqual(try XCTUnwrap(result.cardiac), 33.2, accuracy: 0.001)
        XCTAssertEqual(result.biological, 31.6, accuracy: 0.001)
    }

    func testScansWithoutRecoveryAreSkippedNotCountedAsZero() throws {
        let result = try XCTUnwrap(estimate(scans: [scan(0), scan(1, recovery: 20), scan(2)]))

        XCTAssertEqual(try XCTUnwrap(result.cardiac), 33.2, accuracy: 0.001)
    }

    func testRecoveryNeedsARealRecentPeak() {
        XCTAssertNil(AgeEngine.heartRateRecovery(peak: nil, current: 70, minutesSinceWorkout: 30))
        XCTAssertNil(AgeEngine.heartRateRecovery(peak: 72, current: 70, minutesSinceWorkout: 30))
        XCTAssertNil(AgeEngine.heartRateRecovery(peak: 150, current: 70, minutesSinceWorkout: 200))
        XCTAssertEqual(AgeEngine.heartRateRecovery(peak: 150, current: 130, minutesSinceWorkout: 5), 20)
    }

    // MARK: Blending across scans

    func testSingleScanIsUsedAsIs() {
        XCTAssertEqual(AgeEngine.blend([20]), 20)
        XCTAssertNil(AgeEngine.blend([]))
    }

    func testSecondScanMovesTheValueByItsWeight() throws {
        let result = try XCTUnwrap(estimate(scans: [scan(0, breathing: 12), scan(1, breathing: 20)]))

        // 12 * 0.65 + 20 * 0.35 = 14.8 breaths, so (14.8 - 14) * 0.8 = 0.64 years.
        XCTAssertEqual(try XCTUnwrap(AgeEngine.blend([12, 20])), 14.8, accuracy: 0.0001)
        XCTAssertEqual(result.pulmonary, 30.6, accuracy: 0.001)
    }

    func testBlendFollowsCaptureTimeNotArrayOrder() {
        let earlier = scan(0, breathing: 12)
        let later = scan(1, breathing: 20)

        XCTAssertEqual(estimate(scans: [earlier, later]), estimate(scans: [later, earlier]))
    }

    func testRepeatedScansConvergeOnTheNewValue() throws {
        let scans = [scan(0, breathing: 12)] + (1...20).map { scan($0, breathing: 20) }
        let result = try XCTUnwrap(estimate(scans: scans))

        XCTAssertEqual(result.pulmonary, 34.8, accuracy: 0.05)
    }

    func testSameInputsAlwaysGiveTheSameResult() {
        let scans = [scan(0, breathing: 16, recovery: 18), scan(1, breathing: 13)]
        let health = HealthSnapshot(sleepHours: 6, stepCount: 5_000, hrvSDNN: 40)

        XCTAssertEqual(estimate(scans: scans, health: health), estimate(scans: scans, health: health))
    }

    // MARK: Clamping bounds

    func testPulmonaryAndBiologicalAgeAreCappedAboveChronologicalAge() throws {
        let health = HealthSnapshot(sleepHours: 2, stepCount: 0)
        let result = try XCTUnwrap(estimate(scans: [scan(breathing: 60)], health: health))

        XCTAssertEqual(result.pulmonary, 42, accuracy: 0.001)
        XCTAssertEqual(result.biological, 42, accuracy: 0.001)
    }

    func testAgesAreCappedBelowChronologicalAge() throws {
        let health = HealthSnapshot(sleepHours: 9, stepCount: 30_000, hrvSDNN: 200)
        let result = try XCTUnwrap(estimate(scans: [scan(breathing: 0, recovery: 35)], health: health))

        XCTAssertEqual(result.pulmonary, 20, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.cardiac), 20, accuracy: 0.001)
        XCTAssertEqual(result.biological, 22, accuracy: 0.001)
    }

    func testAgesNeverLeaveEighteenToNinety() throws {
        let young = try XCTUnwrap(estimate(age: 20, scans: [scan(breathing: 0)]))
        let old = try XCTUnwrap(estimate(age: 85, scans: [scan(breathing: 60)]))

        XCTAssertEqual(young.pulmonary, 18, accuracy: 0.001)
        XCTAssertEqual(old.pulmonary, 90, accuracy: 0.001)
    }

    func testRecoveryAboveTheCeilingAddsNothingExtra() {
        XCTAssertEqual(estimate(scans: [scan(recovery: 35)]), estimate(scans: [scan(recovery: 120)]))
    }

    // MARK: Factor breakdown

    func testFactorsAddUpToBiologicalAge() throws {
        let health = HealthSnapshot(sleepHours: 6.5, stepCount: 6_000, hrvSDNN: 48)
        let result = try XCTUnwrap(estimate(scans: [scan(breathing: 16, recovery: 24)], health: health))
        let total = result.factors.reduce(0) { $0 + $1.years }

        XCTAssertEqual(result.factors.count, 5)
        XCTAssertEqual(result.biological, 30 + total, accuracy: 0.05)
    }
}
