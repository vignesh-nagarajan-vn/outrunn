//
//  SettingsView.swift
//  outrunn
//

import SwiftUI

struct SettingsView: View {
    var state: UserRecoveryState

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var ageText: String = ""
    @State private var saveMessage: String?
    @State private var showResetConfirm = false
    @State private var isLinkingHealth = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case age
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Neu.canvas.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        sectionTitle("Profile")

                        VStack(alignment: .leading, spacing: 14) {
                            labeledField("Name", text: $name, field: .name)
                            labeledField("Age", text: $ageText, field: .age)
                                .keyboardType(.numberPad)
                        }
                        .padding(16)
                        .background(ConvexShape(shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))

                        Button {
                            saveProfile()
                        } label: {
                            Text(saveMessage ?? "Save Profile")
                                .font(Neu.button(17))
                                .foregroundStyle(Neu.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(NeuButtonStyle())

                        sectionTitle("Apple Health")

                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: healthBinding) {
                                Text("Use Apple Health")
                                    .font(Neu.body(16))
                                    .foregroundStyle(Neu.ink)
                            }
                            .tint(Neu.accent)
                            .disabled(isLinkingHealth)

                            Text(healthDetail)
                                .font(Neu.body(13))
                                .foregroundStyle(Neu.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .background(ConvexShape(shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))

                        sectionTitle("Data")

                        VStack(spacing: 0) {
                            infoRow("Scans Stored", value: "\(state.scanHistory.count)")
                            Divider().opacity(0.15)
                            infoRow("Age Readings", value: "\(state.ageHistory.count)")
                        }
                        .padding(16)
                        .background(ConvexShape(shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))

                        Button {
                            showResetConfirm = true
                        } label: {
                            Text("Reset Data")
                                .font(Neu.button(17))
                                .foregroundStyle(Neu.older)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(NeuButtonStyle())
                    }
                    .padding(22)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        saveProfile()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Reset Data", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Reset Today", role: .destructive) {
                    state.resetData(.day)
                }
                Button("Reset This Week", role: .destructive) {
                    state.resetData(.week)
                }
                Button("Reset All Time", role: .destructive) {
                    state.resetData(.all)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes scans, age readings, and the plan for the selected period. Your profile stays.")
            }
            .onAppear {
                name = state.userName
                ageText = String(format: "%.0f", state.chronologicalAge)
            }
        }
    }

    private var healthDetail: String {
        if let status = state.healthKitStatus {
            return status
        }
        return "Read-only. Adds sleep, steps, resting heart rate, and HRV to your estimate. Off means scans only."
    }

    private var healthBinding: Binding<Bool> {
        Binding(
            get: { state.isHealthLinked },
            set: { isOn in
                if isOn {
                    Task { await linkHealth() }
                } else {
                    state.unlinkHealth()
                }
            }
        )
    }

    private func linkHealth() async {
        isLinkingHealth = true
        defer { isLinkingHealth = false }

        let health = HealthKitManager.shared
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            health.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard granted, let vitals = await health.fetchLatestVitals() else {
            state.unlinkHealth(reason: health.statusMessage ?? "Could not read Apple Health.")
            return
        }
        state.applyHealthKitVitals(vitals)
    }

    private func saveProfile() {
        focusedField = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedAge = Double(ageText.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? state.chronologicalAge
        state.updateProfile(
            name: trimmedName.isEmpty ? state.userName : trimmedName,
            chronologicalAge: min(90, max(18, parsedAge))
        )
        name = state.userName
        ageText = String(format: "%.0f", state.chronologicalAge)
        saveMessage = "Saved"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if saveMessage == "Saved" {
                saveMessage = nil
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Neu.display(22))
            .italic()
            .foregroundStyle(Neu.ink)
    }

    private func labeledField(_ title: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Neu.label(13))
                .foregroundStyle(Neu.muted)
            NeuField(placeholder: title, text: text)
                .focused($focusedField, equals: field)
        }
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(Neu.body(16))
                .foregroundStyle(Neu.ink)
            Spacer()
            Text(value)
                .font(Neu.body(15))
                .foregroundStyle(Neu.muted)
        }
        .padding(.vertical, 10)
    }
}

#Preview {
    @Previewable @State var state = UserRecoveryState.preview
    SettingsView(state: state)
}
