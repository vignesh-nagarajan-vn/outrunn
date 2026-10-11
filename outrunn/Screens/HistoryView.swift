//
//  HistoryView.swift
//  outrunn
//

import SwiftUI

struct HistoryView: View {
    var store: Store
    var onOpenSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: ShellLayout.pageSpacing) {
            ShellHeader(title: "History") {
                SettingsGearButton(action: onOpenSettings)
            }

            if store.data.readings.isEmpty {
                Spacer(minLength: 0)
                Text("Scans you complete will land here and stay stored.")
                    .font(Neu.body(16))
                    .foregroundStyle(Neu.muted)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(store.data.readings.reversed()) { reading in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(reading.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                                    .font(Neu.body(13))
                                    .foregroundStyle(Neu.muted)
                                Text("Real \(fmt(reading.chronological))  ·  Bio \(fmt(reading.biological))  ·  Cardiac \(fmt(reading.cardiac))  ·  Pulmonary \(fmt(reading.pulmonary))")
                                    .font(Neu.body())
                                    .foregroundStyle(Neu.ink)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ConvexShape(shape: RoundedRectangle(cornerRadius: 20, style: .continuous)))
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(.horizontal, ShellLayout.horizontalPadding)
        .padding(.top, ShellLayout.topPadding)
    }

    /// Two dashes mean the value could not be estimated for that scan.
    private func fmt(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "--"
    }
}

#Preview {
    @Previewable @State var store = Store.preview
    HistoryView(store: store)
}
