//
//  RootView.swift
//  outrunn
//

import SwiftUI

enum AppRoute: Equatable {
    case splash
    case onboarding
    case main
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var route: AppRoute = .splash
    @State private var recoveryState = UserRecoveryState.restored()

    var body: some View {
        ZStack {
            Neu.canvas.ignoresSafeArea()

            switch route {
            case .splash:
                SplashView {
                    route = recoveryState.hasProfile ? .main : .onboarding
                }
                .transition(pushTransition)

            case .onboarding:
                OnboardingView { name, age in
                    recoveryState.updateProfile(name: name, chronologicalAge: age)
                    route = .main
                }
                .transition(pushTransition)

            case .main:
                MainShellView(state: recoveryState)
                    .transition(pushTransition)
            }
        }
        .preferredColorScheme(.light)
        .animation(.spring(response: 0.52, dampingFraction: 0.88), value: route)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                recoveryState.persistSoon()
            }
        }
    }

    private var pushTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

#Preview {
    RootView()
}
