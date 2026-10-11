//
//  InsightsView.swift
//  outrunn
//

import SwiftUI

struct InsightsView: View {
    var store: Store
    var coach: Coach
    var onOpenSettings: () -> Void = {}
    var onOpenRoute: (RoadrunnerRoute) -> Void = { _ in }
    var isVisible: Bool = true

    @State private var roadrunnerDraft = ""
    @FocusState private var roadrunnerFocused: Bool
    @State private var planJumpCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShellHeader(title: "Insights") {
                SettingsGearButton(action: onOpenSettings)
            }
            .padding(.horizontal, ShellLayout.horizontalPadding)
            .padding(.top, ShellLayout.topPadding)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        refreshCard
                        roadrunnerCard

                        if coach.isWritingPlan {
                            HStack(spacing: 12) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Writing a new plan")
                                        .font(Neu.button(16))
                                        .foregroundStyle(Neu.ink)
                                    Text("Reading your latest scan…")
                                        .font(Neu.body(14))
                                        .foregroundStyle(Neu.muted)
                                }
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ConvexShape(shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))
                        }

                        if let plan = store.data.plan {
                            hero(plan)
                                .id("insightsPlan")
                            if !plan.scanVsLifestyle.isEmpty {
                                readableBlock(
                                    kicker: "Scan vs Apple Health",
                                    title: "What the camera saw, vs your week",
                                    body: [plan.scanVsLifestyle, plan.recoveryWindow]
                                        .filter { !$0.isEmpty }
                                        .joined(separator: "\n\n"),
                                    tint: Neu.accent
                                )
                            }
                            if !plan.drivers.isEmpty {
                                Text("What’s moving the number")
                                    .font(Neu.label(13))
                                    .foregroundStyle(Neu.muted)
                                    .textCase(.uppercase)
                                    .tracking(0.6)
                                ForEach(Array(plan.drivers.enumerated()), id: \.offset) { _, driver in
                                    driverRow(driver)
                                }
                            }
                            planSection(title: "Do this today", symbol: "sun.max.fill", tint: Color.orange, items: plan.today)
                            planSection(title: "This week", symbol: "calendar", tint: Neu.accent, items: plan.thisWeek)
                            planSection(title: "Training", symbol: "figure.run", tint: Color(red: 0.86, green: 0.38, blue: 0.40), items: plan.training)
                            planSection(title: "Recovery", symbol: "moon.zzz.fill", tint: Color(red: 0.35, green: 0.55, blue: 0.86), items: plan.recovery)
                            planSection(title: "Long-term improvement", symbol: "chart.line.uptrend.xyaxis", tint: Neu.younger, items: plan.longTerm)
                            if let caution = plan.caution, !caution.isEmpty {
                                readableBlock(kicker: "Keep in mind", title: "Not a diagnosis", body: caution, tint: Neu.older)
                            }
                        } else if !coach.isWritingPlan {
                            readableBlock(
                                kicker: "Plan",
                                title: hasScan ? "No plan yet" : "Scan first",
                                body: hasScan
                                    ? "Tap Repopulate to generate a plan from your latest scan."
                                    : "Complete a scan to unlock a personalized recovery plan.",
                                tint: Neu.accent
                            )
                            .id("insightsPlan")
                        }

                        if let error = coach.planError, !coach.isWritingPlan {
                            readableBlock(kicker: "Coach", title: "Couldn’t finish the plan", body: error, tint: Neu.older)
                        }
                    }
                    .padding(.horizontal, ShellLayout.horizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: isVisible) { _, visible in
                    if !visible {
                        resetRoadrunnerSession()
                    }
                }
                .onChange(of: planJumpCount) { _, _ in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("insightsPlan", anchor: .top)
                    }
                }
            }
        }
    }

    private var refreshCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Last updated")
                    .font(Neu.label(11))
                    .foregroundStyle(Neu.accent)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(lastUpdatedText)
                    .font(Neu.heading(16))
                    .italic()
                    .foregroundStyle(Neu.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let note = compactAccuracyNote {
                    Text(note)
                        .font(Neu.body(12))
                        .foregroundStyle(Neu.muted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if hasScan {
                Button {
                    Task { await coach.refreshPlan() }
                } label: {
                    Text(coach.isWritingPlan ? "Generating…" : "Repopulate")
                        .font(Neu.button(14))
                        .foregroundStyle(Neu.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(NeuButtonStyle())
                .disabled(coach.isWritingPlan)
                .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConvexShape(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
    }

    private var roadrunnerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                RoadrunnerMark(size: 22)
                Text("ask")
                    .font(Neu.heading(16))
                    .italic()
                    .foregroundStyle(Neu.ink)
                BrandWordmark(kind: .roadrunner, size: 16)
                Spacer(minLength: 8)
                if hasScan, !coach.isAnswering, coach.chatError == nil {
                    Text(quotaCopy)
                        .font(Neu.body(11))
                        .foregroundStyle(Neu.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            if !coach.messages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(coach.messages.suffix(8))) { message in
                        roadrunnerBubble(message)
                    }
                }
            }

            if coach.isAnswering {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Checking your scan…")
                        .font(Neu.body(12))
                        .foregroundStyle(Neu.muted)
                }
            }

            if let status = coach.chatError, !coach.isAnswering {
                Text(status)
                    .font(Neu.body(12))
                    .foregroundStyle(Neu.older)
            }

            HStack(spacing: 8) {
                TextField("Where is this? Why did it move?", text: $roadrunnerDraft, axis: .vertical)
                    .font(Neu.body(15))
                    .foregroundStyle(Neu.ink)
                    .lineLimit(1...3)
                    .focused($roadrunnerFocused)
                    .submitLabel(.send)
                    .onSubmit { sendRoadrunner() }
                    .disabled(coach.isAnswering)

                Button {
                    sendRoadrunner()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(canSendRoadrunner ? Neu.accent : Neu.muted.opacity(0.45))
                }
                .buttonStyle(.plain)
                .disabled(!canSendRoadrunner)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                ConvexShape(
                    shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                    isPressed: true
                )
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConvexShape(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
    }

    private var quotaCopy: String {
        let left = coach.questionsRemaining
        if left == 0 {
            return "None left today"
        }
        return "\(left) left today"
    }

    private func resetRoadrunnerSession() {
        roadrunnerDraft = ""
        roadrunnerFocused = false
        planJumpCount = 0
        coach.resetChat()
    }

    private var hasScan: Bool {
        store.estimate != nil
    }

    private var canSendRoadrunner: Bool {
        !coach.isAnswering
            && !roadrunnerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendRoadrunner() {
        let question = roadrunnerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSendRoadrunner else { return }
        roadrunnerDraft = ""
        roadrunnerFocused = false
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        Task { await coach.ask(question) }
    }

    @ViewBuilder
    private func roadrunnerBubble(_ message: RoadrunnerMessage) -> some View {
        HStack {
            if message.isUser { Spacer(minLength: 28) }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                roadrunnerText(message)
                    .font(Neu.body())
                    .foregroundStyle(Neu.ink)
                    .multilineTextAlignment(message.isUser ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: 280, alignment: message.isUser ? .trailing : .leading)
                    .background(
                        ConvexShape(
                            shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                            isPressed: message.isUser
                        )
                    )
                if let route = message.route, !message.isUser {
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        if route == .insights {
                            planJumpCount += 1
                        } else {
                            onOpenRoute(route)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(route.buttonTitle)
                            Image(systemName: "arrow.up.right")
                        }
                        .font(Neu.label(14))
                        .foregroundStyle(Neu.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !message.isUser { Spacer(minLength: 28) }
        }
    }

    private func roadrunnerText(_ message: RoadrunnerMessage) -> Text {
        guard !message.isUser else { return Text(message.text) }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: message.text, options: options) {
            return Text(attributed)
        }
        return Text(message.text)
    }

    private var lastUpdatedText: String {
        guard let plan = store.data.plan else {
            return "Not generated yet"
        }
        return plan.generatedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var compactAccuracyNote: String? {
        if !hasScan {
            return "Scan first to generate a plan."
        }
        if store.data.plan == nil {
            return "Tap Repopulate to generate a plan."
        }
        if let scan = store.latestScan,
           let plan = store.data.plan,
           scan.capturedAt > plan.generatedAt.addingTimeInterval(2) {
            return "Newer scan in. Repopulate to match."
        }
        return nil
    }

    private func hero(_ plan: CoachPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your read")
                .font(Neu.label(12))
                .foregroundStyle(Neu.accent)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(plan.headline)
                .font(Neu.display(26))
                .italic()
                .foregroundStyle(Neu.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(plan.summary)
                .font(Neu.body(16))
                .foregroundStyle(Neu.ink.opacity(0.82))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConvexShape(shape: RoundedRectangle(cornerRadius: 24, style: .continuous)))
    }

    private func readableBlock(kicker: String, title: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kicker)
                .font(Neu.label(11))
                .foregroundStyle(tint)
                .textCase(.uppercase)
                .tracking(0.7)
            Text(title)
                .font(Neu.heading(20))
                .italic()
                .foregroundStyle(Neu.ink)
            Text(body)
                .font(Neu.body())
                .foregroundStyle(Neu.ink.opacity(0.8))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConvexShape(shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))
    }

    private func driverRow(_ driver: CoachDriver) -> some View {
        let color: Color = {
            switch driver.impact.lowercased() {
            case "helping": return Neu.younger
            case "hurting": return Neu.older
            default: return Neu.muted
            }
        }()
        return HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(driver.factor)
                    .font(Neu.button(16))
                    .foregroundStyle(Neu.ink)
                Text(driver.note)
                    .font(Neu.body(14))
                    .foregroundStyle(Neu.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConvexShape(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
    }

    private func planSection(title: String, symbol: String, tint: Color, items: [String]) -> some View {
        guard !items.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(Neu.heading(20))
                        .italic()
                        .foregroundStyle(Neu.ink)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(Neu.label(13))
                            .foregroundStyle(tint)
                            .frame(width: 22, height: 22)
                            .background(tint.opacity(0.15), in: Circle())
                        Text(item)
                            .font(Neu.body())
                            .foregroundStyle(Neu.ink.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ConvexShape(shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))
        )
    }
}

#Preview {
    @Previewable @State var store = Store.preview
    InsightsView(store: store, coach: Coach(store: store))
}
