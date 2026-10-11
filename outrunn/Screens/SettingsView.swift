//
//  SettingsView.swift
//  outrunn
//

import SwiftUI

struct SettingsView: View {
    var store: Store
    var coach: Coach

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
                            infoRow("Scans Stored", value: "\(store.data.scans.count)")
                            Divider().opacity(0.15)
                            infoRow("Age Readings", value: "\(store.data.readings.count)")
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
                    reset(.day)
                }
                Button("Reset This Week", role: .destructive) {
                    reset(.week)
                }
                Button("Reset All Time", role: .destructive) {
                    reset(.all)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes scans, age readings, and the plan for the selected period. Your profile stays.")
            }
            .onAppear {
                name = store.data.profile?.name ?? ""
                ageText = String(format: "%.0f", store.age)
            }
        }
    }

    /// What Apple Health last returned, or why nothing is shown.
    private var healthDetail: String {
        if let status = store.healthStatus {
            return status
        }
        guard store.data.healthEnabled else {
            return "Read-only. Adds sleep, steps, HRV, and heart rate recovery to your estimate. Off means scans only."
        }
        guard let health = store.data.health else {
            return "Reading Apple Health…"
        }
        var parts: [String] = []
        if let hours = health.sleepHours { parts.append(String(format: "sleep %.1f h", hours)) }
        if let steps = health.stepCount { parts.append("\(steps) steps") }
        if let rhr = health.restingHeartRate { parts.append("resting HR \(rhr)") }
        if let sdnn = health.hrvSDNN { parts.append(String(format: "HRV %.0f ms", sdnn)) }
        if let peak = health.peakHeartRate { parts.append("recent peak HR \(peak)") }
        return "Last read: " + parts.joined(separator: ", ") + ". Anything not listed had no data."
    }

    private var healthBinding: Binding<Bool> {
        Binding(
            get: { store.data.healthEnabled },
            set: { isOn in
                if isOn {
                    isLinkingHealth = true
                    Task {
                        await store.enableHealth()
                        isLinkingHealth = false
                    }
                } else {
                    store.disableHealth()
                }
            }
        )
    }

    private func reset(_ scope: DataResetScope) {
        store.reset(scope)
        coach.resetChat()
    }

    private func saveProfile() {
        focusedField = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedAge = Double(ageText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? store.age
        store.saveProfile(
            name: trimmedName.isEmpty ? (store.data.profile?.name ?? "") : trimmedName,
            age: parsedAge
        )
        name = store.data.profile?.name ?? ""
        ageText = String(format: "%.0f", store.age)
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
    @Previewable @State var store = Store.preview
    SettingsView(store: store, coach: Coach(store: store))
}
