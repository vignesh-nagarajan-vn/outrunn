//
//  Coach.swift
//  outrunn
//
//  Sends numbers (never video) to Gemini for a written plan and for
//  roadrunner answers. The model explains the engine's ages. It never
//  changes them.
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
            let plan = try await GeminiClient.plan(for: snapshot)
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
            let answer = try await GeminiClient.answer(asked, brief: RoadrunnerGuide.brief(for: store))
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

private enum GeminiClient {
    private static let model = "gemini-3.6-flash"

    private static var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private struct PlanPayload: Decodable {
        var headline: String?
        var summary: String
        var scanVsLifestyle: String?
        var recoveryWindow: String?
        var drivers: [CoachDriver]?
        var plan: Sections?
        var caution: String?

        struct Sections: Decodable {
            var today: [String]?
            var thisWeek: [String]?
            var training: [String]?
            var recovery: [String]?
            var longTerm: [String]?
        }
    }

    static func plan(for snapshot: CoachSnapshot) async throws -> CoachPlan {
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        let text = try await generate(
            systemPrompt: planPrompt,
            userText: "Explain this outrunn snapshot and return JSON only:\n\(json)",
            temperature: 0.4,
            json: true
        )
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = try JSONDecoder().decode(PlanPayload.self, from: Data(cleaned.utf8))
        return CoachPlan(
            generatedAt: .now,
            headline: parsed.headline ?? parsed.summary,
            summary: parsed.summary,
            scanVsLifestyle: parsed.scanVsLifestyle ?? "",
            recoveryWindow: parsed.recoveryWindow ?? "",
            drivers: parsed.drivers ?? [],
            today: parsed.plan?.today ?? [],
            thisWeek: parsed.plan?.thisWeek ?? [],
            training: parsed.plan?.training ?? [],
            recovery: parsed.plan?.recovery ?? [],
            longTerm: parsed.plan?.longTerm ?? [],
            caution: parsed.caution
        )
    }

    static func answer(_ question: String, brief: String) async throws -> (text: String, route: RoadrunnerRoute?) {
        let raw = try await generate(
            systemPrompt: roadrunnerPrompt,
            userText: "Athlete brief:\n\(brief)\n\nQuestion:\n\(question)",
            temperature: 0.5,
            json: false
        )
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var route: RoadrunnerRoute?
        if let match = text.range(
            of: #"\n?open:\s*([a-z]+)\s*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let key = String(text[match])
                .replacingOccurrences(of: "open:", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            route = RoadrunnerRoute(rawValue: key)
            text.removeSubrange(match)
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), route)
    }

    private static func generate(
        systemPrompt: String,
        userText: String,
        temperature: Double,
        json: Bool
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "Coach", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing Gemini API key."])
        }
        var config: [String: Any] = ["temperature": temperature]
        if json {
            config["responseMimeType"] = "application/json"
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": userText]]]],
            "generationConfig": config
        ]

        guard let url = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        ) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw NSError(
                domain: "Coach",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: "Gemini request failed (\(status))."]
            )
        }

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = object?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]] ?? []
        let text = parts.compactMap { part -> String? in
            if part["thought"] as? Bool == true { return nil }
            return part["text"] as? String
        }.joined()
        guard !text.isEmpty else { throw URLError(.cannotParseResponse) }
        return text
    }

    private static let roadrunnerPrompt = """
    You are roadrunner, outrunn's in-app recovery guide.

    Answer only this question. You get a short athlete brief, not chat history and not extra files.

    Stay inside outrunn: this athlete's scan, Real / Biological / Cardiac / Pulmonary Age, Apple Health numbers, and the Insights plan. If the question is outside that, say you only talk about their outrunn data.

    If they ask where something is, or what an existing screen means, reply in 1-2 sentences and end with:
    OPEN: today|insights|history|settings|scan

    For why a number moved or what to do next: use their actual numbers, explain the likely driver, then give concrete next steps. Do not add an OPEN line unless a screen really helps.

    The ages in the brief come from outrunn's engine. Never restate them as different numbers and never estimate an age of your own. If the brief says a value is not available, say there is not enough data. Do not guess it.

    Voice:
    - Complete, useful answers. Do not truncate your thought. Short paragraphs are fine.
    - Names: Real Age, Biological Age, Cardiac Age, Pulmonary Age.
    - No diagnosis, no drugs, no supplements, no invented studies, no JSON.
    """

    private static let planPrompt = """
    You are outrunn's recovery coach. Inputs are numbers only (a phone camera scan plus Apple Health). Never video.

    The ages (biologicalAge, cardiacAge, pulmonaryAge) and the factors list come from outrunn's engine and are final. Each factor is that input's contribution to biologicalAge in years; negative is younger. Explain these numbers. Never output an age of your own and never say the real number should be different.

    Any field that is missing was not measured. Say there is not enough data for it. Do not guess it. If cardiacAge is missing, say Cardiac Age needs Apple Health heart rate data.

    Compare TWO layers:
    1) Scan (scanHeartRate, scanRespiratoryRate, heartRateRecovery, scanHrvRMSSD, stressIndex, scanPulseConfidence): camera physiology at this moment.
    2) Apple Health (restingHeartRate, hrvSDNN, sleepHours, steps): last-day and last-week lifestyle.

    scanHrvRMSSD and hrvSDNN are different HRV measures. Do not compare them to each other as if they were the same unit.

    Use minutesSinceWorkout (set by the user, 0-240) as ground truth for the recovery phase:
    - Under 15 min: elevated heart rate is expected; say the scan reflects incomplete recovery.
    - 15-60 min: heart rate recovery is most meaningful.
    - Hours later: heart rate should be near restingHeartRate; leftover elevation is recovery debt.
    Always mention this window in recoveryWindow.

    heartRateRecovery is the drop from the recent Apple Health peak to the scan heart rate. It is not a clinical one minute test. If sleep or steps are poor, attribute that part of an older age to lifestyle, not to the scan. If scanPulseConfidence is under 70, say the scan signal was weak.

    Voice: warm, specific, plain. Short paragraphs. No diagnosis, no drugs, no supplements.

    Return JSON:
    headline (1 punchy sentence),
    summary (2-4 readable sentences),
    scanVsLifestyle (how the scan and Apple Health agree or disagree),
    recoveryWindow (plain language about time since workout),
    drivers (array of {factor, impact: helping|hurting|neutral, note}, max 4),
    plan {
      today (2-4 bullets),
      thisWeek (2-4 bullets),
      training (2-4 bullets),
      recovery (2-4 bullets),
      longTerm (2-4 bullets about 8-12 week improvement: zone 2 consistency, VO2 work, sleep regularity, strength)
    },
    caution (string or null).
    """
}
