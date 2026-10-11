//
//  RoadrunnerGuide.swift
//  outrunn
//
//  Local answers for "where is X" and "what is my X" so they never
//  cost a model call, plus the short brief sent with real questions.
//

import Foundation

enum RoadrunnerGuide {
    struct Answer {
        var text: String
        var route: RoadrunnerRoute?
    }

    @MainActor
    static func resolve(_ question: String, store: Store) -> Answer? {
        let q = normalize(question)
        guard !q.isEmpty else { return nil }

        if let fact = factAnswer(q, store: store) {
            return fact
        }

        let interpretive = containsAny(q, [
            "why", "should i", "what should", "how can i", "how do i improve",
            "how do i lower", "how do i reduce", "how do i fix", "tonight",
            "what do i do", "what would you"
        ])
        let wantsPlace = containsAny(q, [
            "where", "find", "take me", "open", "go to", "show me", "which tab",
            "which page", "navigate", "bring me", "how do i get", "how do i find",
            "how do i open", "how do i see", "how do i take", "how do i start",
            "how do i scan"
        ])
        guard wantsPlace, !interpretive, let route = route(for: q) else { return nil }
        return Answer(text: copy(for: route), route: route)
    }

    static func isOnTopic(_ question: String) -> Bool {
        let q = normalize(question)
        if containsAny(q, [
            "ignore previous", "ignore all", "system prompt", "you are now",
            "jailbreak", "api key", "developer mode", "repeat this prompt",
            "reveal your", "hidden instructions"
        ]) {
            return false
        }
        return containsAny(q, [
            "age", "scan", "pulse", "heart", "cardiac", "pulmonary", "biological",
            "recovery", "sleep", "stress", "breathing", "hrv", "insight", "plan",
            "train", "workout", "today", "history", "health", "outrun", "roadrunner",
            "roadruner", "baseline", "camera", "zone", "steps", "tonight", "this week",
            "should i", "why is", "what should", "how can i", "apple", "older",
            "younger", "rhr", "vo2", "breath", "resting", "hrr"
        ])
    }

    /// The few lines of context sent with a question. Anything not measured is named as such.
    @MainActor
    static func brief(for store: Store) -> String {
        guard let estimate = store.estimate else { return "No scan yet." }
        let age = store.age
        var lines = [
            "Real Age: \(years(age))",
            "Biological Age: \(years(estimate.biological)) (\(vsReal(estimate.biological, age: age)))",
            "Pulmonary Age: \(years(estimate.pulmonary)) (\(vsReal(estimate.pulmonary, age: age)))"
        ]
        if let cardiac = estimate.cardiac {
            lines.append("Cardiac Age: \(years(cardiac)) (\(vsReal(cardiac, age: age)))")
        } else {
            lines.append("Cardiac Age: not available, not enough heart rate data")
        }
        if let scan = store.latestScan {
            var parts = [
                "pulse \(scan.heartRate) bpm",
                "breathing \(Int(scan.respiratoryRate.rounded()))/min",
                scan.heartRateRecovery.map { "heart rate recovery \($0) beats" } ?? "heart rate recovery not available",
                "pulse confidence \(Int(scan.pulseConfidence.rounded()))",
                "\(scan.minutesSinceWorkout) min after workout"
            ]
            if let rmssd = scan.rmssd {
                parts.append("scan HRV (RMSSD) \(Int(rmssd.rounded())) ms")
            }
            if let stress = scan.stressIndex {
                parts.append("stress index \(Int(stress.rounded()))")
            }
            lines.append("Last scan: " + parts.joined(separator: ", "))
        }
        if let health = store.data.health {
            var parts: [String] = []
            if let hours = health.sleepHours { parts.append("sleep \(String(format: "%.1f", hours)) h") }
            if let rhr = health.restingHeartRate { parts.append("resting HR \(rhr)") }
            if let sdnn = health.hrvSDNN { parts.append("HRV (SDNN) \(Int(sdnn.rounded())) ms") }
            if let steps = health.stepCount { parts.append("steps \(steps)") }
            lines.append("Apple Health: " + parts.joined(separator: ", "))
        } else {
            lines.append("Apple Health: not connected")
        }
        if let plan = store.data.plan {
            lines.append("Plan: \(plan.headline)")
            if let today = plan.today.first {
                lines.append("Today: \(today)")
            }
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    private static func factAnswer(_ q: String, store: Store) -> Answer? {
        let askingMine = containsAny(q, ["what is my", "whats my", "how old am i", "what are my"])
        guard askingMine, let estimate = store.estimate else { return nil }
        let age = store.age
        if containsAny(q, ["biological"]) {
            return Answer(
                text: "Biological Age is \(years(estimate.biological)), \(vsReal(estimate.biological, age: age)).",
                route: .today
            )
        }
        if containsAny(q, ["cardiac", "heart age"]) {
            guard let cardiac = estimate.cardiac else {
                return Answer(
                    text: "There is not enough data for Cardiac Age yet. It needs heart rate recovery or HRV from Apple Health.",
                    route: .settings
                )
            }
            return Answer(text: "Cardiac Age is \(years(cardiac)), \(vsReal(cardiac, age: age)).", route: .today)
        }
        if containsAny(q, ["pulmonary", "lung"]) {
            return Answer(
                text: "Pulmonary Age is \(years(estimate.pulmonary)), \(vsReal(estimate.pulmonary, age: age)).",
                route: .today
            )
        }
        if containsAny(q, ["real age", "calendar"]) {
            return Answer(text: "Real Age is \(years(age)).", route: .today)
        }
        guard let scan = store.latestScan else { return nil }
        if containsAny(q, ["pulse", "heart rate", " bpm"]) {
            return Answer(text: "Last scan pulse was \(scan.heartRate) bpm.", route: .today)
        }
        if containsAny(q, ["breathing", "respiratory"]) {
            return Answer(
                text: "Last scan breathing was \(Int(scan.respiratoryRate.rounded())) breaths/min.",
                route: .today
            )
        }
        if containsAny(q, ["stress"]), let stress = scan.stressIndex {
            return Answer(text: "Last scan stress index was \(Int(stress.rounded())).", route: .today)
        }
        return nil
    }

    private static func route(for q: String) -> RoadrunnerRoute? {
        if containsAny(q, ["scan", "camera", "baseline"]) {
            return .scan
        }
        if containsAny(q, ["history", "past scan", "previous scan", "old scan", "past result"]) {
            return .history
        }
        if containsAny(q, ["settings", "profile", "reset", "apple health", "healthkit", "gear"]) {
            return .settings
        }
        if containsAny(q, ["insights", "my plan", "the plan"]) {
            return .insights
        }
        if containsAny(q, [
            "today", "chart", "graph", "trend", "numbers", "pulse", "breathing", "stress",
            "cardiac age", "biological age", "pulmonary age", "real age", "adding years"
        ]) {
            return .today
        }
        return nil
    }

    private static func copy(for route: RoadrunnerRoute) -> String {
        switch route {
        case .scan:
            "Take a scan from Today. I’ll open it."
        case .today:
            "Your ages, the trend chart, last scan stats, and what is adding years are all on Today."
        case .history:
            "Past readings are on History."
        case .settings:
            "Profile, Apple Health, and reset are behind the gear icon."
        case .insights:
            "Your plan is on this Insights page, just below the chat."
        }
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "['’]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsAny(_ q: String, _ phrases: [String]) -> Bool {
        phrases.contains { q.contains($0) }
    }

    private static func years(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func vsReal(_ value: Double, age: Double) -> String {
        let delta = value - age
        if abs(delta) < 0.3 { return "about the same as Real Age" }
        if delta > 0 {
            return String(format: "%.1f years older than Real Age", delta)
        }
        return String(format: "%.1f years younger than Real Age", abs(delta))
    }
}
