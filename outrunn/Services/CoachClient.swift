//
//  CoachClient.swift
//  outrunn
//
//  Sends numbers (never video) to the outrunn coach proxy for a written plan
//  and for roadrunner answers. The prompts and the model key live on the
//  server. The model explains the engine's ages. It never changes them.
//

import Foundation
import Observation

struct CoachDriver: Hashable, Codable {
    var factor: String
    var impact: String
    var note: String
}

struct CoachPlan: Hashable, Codable {
    var generatedAt: Date
    var headline: String
    var summary: String
    var scanVsLifestyle: String
    var recoveryWindow: String
    var drivers: [CoachDriver]
    var today: [String]
    var thisWeek: [String]
    var training: [String]
    var recovery: [String]
    var longTerm: [String]
    var caution: String?
}

struct RoadrunnerMessage: Identifiable, Hashable {
    var id = UUID()
    var isUser: Bool
    var text: String
    var route: RoadrunnerRoute?
}

enum RoadrunnerRoute: String, Hashable {
    case today
    case insights
    case history
    case settings
    case scan

    var buttonTitle: String {
        switch self {
        case .today: "Open Today"
        case .insights: "See plan below"
        case .history: "Open History"
        case .settings: "Open Settings"
        case .scan: "Take a scan"
        }
    }
}

/// The numbers the coach is allowed to see. Missing values are left out, not guessed.
struct CoachSnapshot: Encodable {
    struct Factor: Encodable {
        var name: String
        var years: Double
    }

    var chronologicalAge: Double
    var biologicalAge: Double
    var cardiacAge: Double?
    var pulmonaryAge: Double
    var factors: [Factor]
    var scanCount: Int
    var minutesSinceWorkout: Int
    var scanHeartRate: Int
    var scanRespiratoryRate: Double
    var scanPulseConfidence: Double
    var heartRateRecovery: Int?
    var scanHrvRMSSD: Double?
    var stressIndex: Double?
    var sleepHours: Double?
    var steps: Int?
    var restingHeartRate: Int?
    var hrvSDNN: Double?

    @MainActor
    init?(store: Store) {
        guard let estimate = store.estimate, let scan = store.latestScan else { return nil }
        let health = store.data.health
        chronologicalAge = store.age
        biologicalAge = estimate.biological
        cardiacAge = estimate.cardiac
        pulmonaryAge = estimate.pulmonary
        factors = estimate.factors.map { Factor(name: $0.title, years: ($0.years * 10).rounded() / 10) }
        scanCount = store.data.scans.count
        minutesSinceWorkout = scan.minutesSinceWorkout
        scanHeartRate = scan.heartRate
        scanRespiratoryRate = scan.respiratoryRate
        scanPulseConfidence = scan.pulseConfidence
        heartRateRecovery = scan.heartRateRecovery
        scanHrvRMSSD = scan.rmssd
        stressIndex = scan.stressIndex
        sleepHours = health?.sleepHours
        steps = health?.stepCount
        restingHeartRate = health?.restingHeartRate
        hrvSDNN = health?.hrvSDNN
    }
}

@Observable
final class Coach {
    static let dailyQuestionLimit = 8
    private static let maxQuestionCharacters = 240

    private let store: Store

    private(set) var isWritingPlan = false
    private(set) var planError: String?
    private(set) var messages: [RoadrunnerMessage] = []
    private(set) var isAnswering = false
    private(set) var chatError: String?
    private var chatGeneration = 0

    init(store: Store) {
        self.store = store
    }

    var questionsRemaining: Int {
        store.questionsRemaining(limit: Self.dailyQuestionLimit)
    }

    func refreshPlan() async {
        guard !isWritingPlan, let snapshot = CoachSnapshot(store: store) else { return }
        isWritingPlan = true
        planError = nil
        defer { isWritingPlan = false }

        do {
            let plan = try await CoachClient.plan(for: snapshot)
            store.setPlan(plan)
        } catch {
            planError = error.localizedDescription
        }
    }

    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let asked = String(trimmed.prefix(Self.maxQuestionCharacters))
        let generation = chatGeneration
        messages.append(RoadrunnerMessage(isUser: true, text: asked))
        chatError = nil

        func reply(_ text: String, route: RoadrunnerRoute? = nil) {
            guard generation == chatGeneration else { return }
            messages.append(RoadrunnerMessage(isUser: false, text: text, route: route))
        }

        if let local = RoadrunnerGuide.resolve(asked, store: store) {
            reply(local.text, route: local.route)
            return
        }
        if !RoadrunnerGuide.isOnTopic(asked) {
            reply("I only talk about your outrunn scan, ages, Apple Health numbers, and Insights plan.")
            return
        }
        guard store.estimate != nil else {
            reply("Scan first from Today. That’s how outrunn gets your ages and plan.", route: .scan)
            return
        }
        guard questionsRemaining > 0 else {
            reply("That’s today’s question limit. Finding a screen still works. Come back tomorrow for more.")
            return
        }
        guard !isAnswering else { return }
        isAnswering = true
        defer { isAnswering = false }

        do {
            let answer = try await CoachClient.answer(asked, brief: RoadrunnerGuide.brief(for: store))
            guard generation == chatGeneration else { return }
            store.countQuestion()
            reply(answer.text, route: answer.route)
        } catch {
            guard generation == chatGeneration else { return }
            chatError = error.localizedDescription
        }
    }

    /// Chat is never saved. Leaving Insights or resetting data clears it.
    func resetChat() {
        chatGeneration += 1
        messages = []
        chatError = nil
        isAnswering = false
        planError = nil
    }
}

private enum CoachClient {
    /// Set by COACH_BASE_URL in Secrets.xcconfig, for example https://your-project.vercel.app
    private static var baseURL: URL? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "COACH_BASE_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard value.hasPrefix("https://"), !value.contains("your-project") else { return nil }
        return URL(string: value)
    }

    private struct PlanRequest: Encodable {
        var snapshot: CoachSnapshot
    }

    private struct PlanResponse: Decodable {
        var headline: String
        var summary: String
        var scanVsLifestyle: String
        var recoveryWindow: String
        var drivers: [CoachDriver]
        var today: [String]
        var thisWeek: [String]
        var training: [String]
        var recovery: [String]
        var longTerm: [String]
        var caution: String?
    }

    private struct QuestionRequest: Encodable {
        var question: String
        var brief: String
    }

    private struct QuestionResponse: Decodable {
        var text: String
        var route: String?
    }

    private struct ErrorResponse: Decodable {
        var error: String
    }

    static func plan(for snapshot: CoachSnapshot) async throws -> CoachPlan {
        let response: PlanResponse = try await post("api/plan", body: PlanRequest(snapshot: snapshot))
        return CoachPlan(
            generatedAt: .now,
            headline: response.headline,
            summary: response.summary,
            scanVsLifestyle: response.scanVsLifestyle,
            recoveryWindow: response.recoveryWindow,
            drivers: response.drivers,
            today: response.today,
            thisWeek: response.thisWeek,
            training: response.training,
            recovery: response.recovery,
            longTerm: response.longTerm,
            caution: response.caution
        )
    }

    static func answer(_ question: String, brief: String) async throws -> (text: String, route: RoadrunnerRoute?) {
        let response: QuestionResponse = try await post(
            "api/roadrunner",
            body: QuestionRequest(question: question, brief: brief)
        )
        return (response.text, response.route.flatMap(RoadrunnerRoute.init(rawValue:)))
    }

    private static func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body
    ) async throws -> Response {
        guard let baseURL else {
            throw failure("The coach is not set up. Add COACH_BASE_URL to Secrets.xcconfig.")
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
            throw failure(message ?? "The coach request failed (\(status)).")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Coach", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
