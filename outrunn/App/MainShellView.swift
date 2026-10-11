//
//  MainShellView.swift
//  outrunn
//

import SwiftUI

enum ShellTab: Hashable {
    case today
    case insights
    case history
}

struct MainShellView: View {
    var state: UserRecoveryState

    @State private var tab: ShellTab = .today
    @State private var showSettings = false
    @State private var scanRequestCount = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                TodayView(
                    state: state,
                    onOpenSettings: { showSettings = true },
                    scanRequestCount: scanRequestCount
                )
                    .opacity(tab == .today ? 1 : 0)
                    .allowsHitTesting(tab == .today)

                InsightsView(
                    state: state,
                    onOpenSettings: { showSettings = true },
                    onOpenRoute: openRoute,
                    isVisible: tab == .insights
                )
                    .opacity(tab == .insights ? 1 : 0)
                    .allowsHitTesting(tab == .insights)

                HistoryView(state: state, onOpenSettings: { showSettings = true })
                    .opacity(tab == .history ? 1 : 0)
                    .allowsHitTesting(tab == .history)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 8)
        }
        .background(Neu.canvas.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.18), value: tab)
        .sheet(isPresented: $showSettings) {
            SettingsView(state: state)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.today, icon: "house.fill", title: "Today")
            tabButton(.insights, icon: "sparkles", title: "Insights")
            tabButton(.history, icon: "clock", title: "History")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(height: 72)
        .background(
            ConvexShape(shape: Capsule())
        )
    }

    private func tabButton(_ value: ShellTab, icon: String, title: String) -> some View {
        let selected = tab == value
        let isInsights = value == .insights
        return Button {
            tab = value
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isInsights {
                        Circle()
                            .fill(selected ? Neu.accent.opacity(0.32) : Neu.accent.opacity(0.18))
                            .frame(width: 38, height: 38)
                    }
                    Image(systemName: icon)
                        .font(.system(size: isInsights ? 17 : 18, weight: .semibold))
                        .foregroundStyle(isInsights || selected ? Neu.accent : Neu.muted)
                        .symbolEffect(.pulse, options: .repeating.speed(0.35), isActive: isInsights && !selected)
                }
                Text(title)
                    .font(Neu.tab(prominent: isInsights))
                    .foregroundStyle(isInsights || selected ? Neu.accent : Neu.muted.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func openRoute(_ route: RoadrunnerRoute) {
        switch route {
        case .today:
            tab = .today
        case .insights:
            tab = .insights
        case .history:
            tab = .history
        case .settings:
            showSettings = true
        case .scan:
            tab = .today
            scanRequestCount += 1
        }
    }
}

#Preview {
    @Previewable @State var state = UserRecoveryState.preview
    MainShellView(state: state)
}
