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
    @State private var store: Store
    @State private var coach: Coach

    init() {
        let store = Store()
        _store = State(initialValue: store)
        _coach = State(initialValue: Coach(store: store))
    }

    var body: some View {
        ZStack {
            Neu.canvas.ignoresSafeArea()

            switch route {
            case .splash:
                SplashView {
                    route = store.data.profile == nil ? .onboarding : .main
                }
                .transition(pushTransition)

            case .onboarding:
                OnboardingView { name, age in
                    store.saveProfile(name: name, age: age)
                    route = .main
                }
                .transition(pushTransition)

            case .main:
                MainShellView(store: store, coach: coach)
                    .transition(pushTransition)
            }
        }
        .preferredColorScheme(.light)
        .animation(.spring(response: 0.52, dampingFraction: 0.88), value: route)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Task { await store.refreshHealth() }
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
