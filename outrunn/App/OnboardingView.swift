//
//  OnboardingView.swift
//  outrunn
//

import SwiftUI

struct OnboardingView: View {
    var onContinue: (String, Double) -> Void

    @State private var name = ""
    @State private var ageText = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var age: Double? {
        guard let value = Double(ageText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (18...90).contains(value)
        else { return nil }
        return value
    }

    private var canContinue: Bool {
        !trimmedName.isEmpty && age != nil
    }

    var body: some View {
        ZStack {
            Neu.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About You")
                        .font(Neu.display(28))
                        .italic()
                        .foregroundStyle(Neu.ink)

                    Text("Your name and age stay on this device. Age is the baseline every estimate is compared against.")
                        .font(Neu.body(16))
                        .foregroundStyle(Neu.muted)
                }
                .padding(.top, 24)

                VStack(spacing: 12) {
                    NeuField(placeholder: "Name", text: $name)
                        .textContentType(.givenName)
                    NeuField(placeholder: "Age (18 to 90)", text: $ageText)
                        .keyboardType(.numberPad)
                }

                Spacer()

                Button {
                    guard let age, canContinue else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onContinue(trimmedName, age)
                } label: {
                    Text("Continue")
                        .font(Neu.button(17))
                        .foregroundStyle(canContinue ? Neu.ink : Neu.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(NeuButtonStyle())
                .disabled(!canContinue)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 22)
        }
        .preferredColorScheme(.light)
    }
}

#Preview {
    OnboardingView { _, _ in }
}
