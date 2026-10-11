//
//  GeminiCoach.swift
//  outrunn
//
//  Sends scan vitals + Apple Health context (never video) to Gemini
//  and stores a structured recovery plan. Gemini explains the engine's
//  numbers. It never changes them.
//

import Foundation

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

private struct GeminiPlanPayload: Decodable {
    var headline: String?
    var summary: String
    var scanVsLifestyle: String?
    var recoveryWindow: String?
    var drivers: [CoachDriver]?
    var plan: Plan?
    var caution: String?

    struct Plan: Decodable {
        var today: [String]?
        var thisWeek: [String]?
        var training: [String]?
        var recovery: [String]?
        var longTerm: [String]?
    }
}

enum GeminiCoach {
    private static let model = "gemini-3.6-flash"
    private static let maxQuestionCharacters = 240

    private static var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    @MainActor
    static func refreshPlan(for state: UserRecoveryState) async {
        guard !apiKey.isEmpty else {
            state.coachStatus = "Missing Gemini API key."
            return
        }
        state.isRefreshingCoach = true
        state.coachStatus = "Gemini is writing your plan…"
        defer { state.isRefreshingCoach = false }

        do {
            let parsed = try await requestPlan(payloadJSON: snapshotJSON(from: state))
            state.latestCoachPlan = CoachPlan(
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
            state.coachStatus = nil
            state.persistSoon()
        } catch {
            state.coachStatus = error.localizedDescription
        }
    }

    @MainActor
    static func askRoadrunner(_ question: String, for state: UserRecoveryState) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let asked = String(trimmed.prefix(maxQuestionCharacters))
        let generation = state.roadrunnerGeneration
        state.roadrunnerMessages.append(RoadrunnerMessage(isUser: true, text: asked))
        state.roadrunnerStatus = nil

        func reply(_ text: String, route: RoadrunnerRoute? = nil) {
            guard generation == state.roadrunnerGeneration else { return }
            state.roadrunnerMessages.append(RoadrunnerMessage(isUser: false, text: text, route: route))
        }

        if let local = RoadrunnerGuide.resolve(asked, state: state) {
            reply(local.text, route: local.route)
            return
        }

        if !RoadrunnerGuide.isOnTopic(asked) {
            reply("I only talk about your outrunn scan, ages, Apple Health numbers, and Insights plan.")
            return
        }

        if !state.hasCompletedBaseline {
            reply("Scan first from Today. That’s how outrunn gets your ages and plan.", route: .scan)
            return
        }

        guard state.roadrunnerAsksRemaining > 0 else {
            reply("That’s today’s question limit. Finding a screen still works. Come back tomorrow for more.")
            return
        }

        guard !apiKey.isEmpty else {
            state.roadrunnerStatus = "Missing Gemini API key."
            return
        }
        guard !state.isAskingRoadrunner else { return }
        state.isAskingRoadrunner = true
        defer { state.isAskingRoadrunner = false }

        do {
            let prompt = """
            Athlete brief:
            \(RoadrunnerGuide.brief(for: state))

            Question:
            \(asked)
            """
            let raw = try await generate(systemPrompt: roadrunnerPrompt, userText: prompt, temperature: 0.5, json: false)
            let parsed = parseRoadrunnerReply(raw)
            guard generation == state.roadrunnerGeneration else { return }
            state.consumeRoadrunnerAsk()
            reply(parsed.text, route: parsed.route)
        } catch {
            guard generation == state.roadrunnerGeneration else { return }
            state.roadrunnerStatus = error.localizedDescription
        }
    }

    @MainActor
    private static func snapshotJSON(from state: UserRecoveryState) -> String {
        let scan = state.latestScan
        let health = state.healthContext
        let chrono = state.chronologicalAge
        let minutes = scan?.minutesSinceAerobicActivity ?? 0
        let recoveryPhase: String
        switch minutes {
        case ..<15: recoveryPhase = "immediate (HR still elevated; do not treat as resting)"
        case 15..<60: recoveryPhase = "early recovery"
        case 60..<24 * 60: recoveryPhase = "same-day recovery"
        default: recoveryPhase = "rested / next-day baseline"
        }

        let object: [String: Any] = [
            "profile": [
                "chronologicalAge": chrono,
                "engineBiologicalAge": state.biologicalAge,
                "engineCardiacAge": state.cardiacAge,
                "enginePulmonaryAge": state.pulmonaryAge
            ],
            "engineFactors": state.factorBreakdown.map {
                ["factor": $0.title, "years": ($0.yearsDelta * 10).rounded() / 10]
            },
            "workoutContext": [
                "minutesSinceAerobicActivity": minutes,
                "recoveryPhase": recoveryPhase
            ],
            "scan": [
                "cameraHeartRate": scan?.cameraHeartRate as Any,
                "respiratoryRate": scan?.respiratoryRate as Any,
                "hrrObserved": scan?.hrrObserved as Any,
                "signalQuality": scan?.signalQuality as Any,
                "stressScore": scan?.stressScore as Any,
                "stressScoreSource": "Presage Baevsky Stress Index from HRV",
                "scanCount": state.scanHistory.count
            ],
            "appleHealth": [
                "linked": health != nil,
                "sleepHours": health?.sleepHours as Any,
                "sleepScore": health?.sleepScore as Any,
                "steps": health?.stepCount as Any,
                "hrvSDNN": health?.hrvSDNN as Any,
                "restingHeartRate": health?.restingHeartRate as Any,
                "activeEnergyKcal": health?.activeEnergyBurned as Any
            ]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func parseRoadrunnerReply(_ raw: String) -> (text: String, route: RoadrunnerRoute?) {
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

    private static func requestPlan(payloadJSON: String) async throws -> GeminiPlanPayload {
        let text = try await generate(
            systemPrompt: systemPrompt,
            userText: "Analyze this outrunn athlete snapshot and return JSON only:\n\(payloadJSON)",
            temperature: 0.4,
            json: true
        )
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        return try JSONDecoder().decode(GeminiPlanPayload.self, from: jsonData)
    }

    private static func generate(
        systemPrompt: String,
        userText: String,
        temperature: Double,
        json: Bool
    ) async throws -> String {
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
                domain: "GeminiCoach",
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

    If they ask where something is, or what an existing screen means, reply in 1–2 sentences and end with:
    OPEN: today|insights|history|settings|scan

    For why a number moved or what to do next: use their actual numbers, explain the likely driver, then give concrete next steps. Do not add an OPEN line unless a screen really helps.

    The ages in the brief come from outrunn's engine. Never restate them as different numbers and never estimate an age of your own.

    Voice:
    - Complete, useful answers. Do not truncate your thought. Short paragraphs are fine.
    - Names: Real Age, Biological Age, Cardiac Age, Pulmonary Age.
    - No diagnosis, no drugs, no supplements, no invented studies, no JSON.
    """

    private static let systemPrompt = """
    You are outrunn's recovery coach. Inputs are numbers only (Presage camera scan + Apple Health). Never video.

    The engine ages (engineBiologicalAge, engineCardiacAge, enginePulmonaryAge) and engineFactors are final. Explain them. Never output an age estimate of your own and never say the real number should be different.

    Compare TWO layers:
    1) Scan (pulse, breathing, HRR, signal quality): camera physiology at this moment.
    2) Apple Health (resting HR, HRV, sleep, steps): last-day/week lifestyle.

    Factor minutesSinceAerobicActivity (user-set Time After Workout slider, 0–240 minutes). Treat it as ground truth for recovery phase:
    - Under 15 min: elevated HR is expected; say the scan reflects incomplete recovery.
    - 15–60 min: heart rate recovery is most meaningful.
    - Hours later: resting HR / HRV should be near the Apple Health baseline; leftover elevation is recovery debt.
    Always mention this recovery window in recoveryWindow.

    A resting camera scan is NOT a treadmill 1-min HRR test. If sleep or steps are poor, attribute that slice of "older" age to lifestyle, not to the scan. If the scan is weak (low signalQuality) say so.

    Voice: warm, specific, not clinical-robotic. Short paragraphs. No diagnosis, no drugs, no supplements.

    Return JSON:
    headline (punchy 1 sentence),
    summary (2–4 sentences, readable),
    scanVsLifestyle (how the scan and Apple Health disagree or agree),
    recoveryWindow (plain language about time since workout),
    drivers (array of {factor, impact: helping|hurting|neutral, note}, max 4),
    plan {
      today (2–4 bullets),
      thisWeek (2–4 bullets),
      training (2–4 bullets),
      recovery (2–4 bullets),
      longTerm (2–4 bullets about 8–12 week improvement: zone-2 consistency, VO2 work, sleep regularity, strength)
    },
    caution (string or null).
    """
}
