import SwiftUI

/// Pro-gated CSV export of grooming sessions over a chosen period, with a live
/// revenue total. Sharing produces a machine CSV (UTF-8 BOM, dot-decimal,
/// comma-separated) via `store.exportSessionsCSV(period:)`.
struct ExportCSVView: View {
    @EnvironmentObject private var store: GroomStore

    @State private var period: ExportPeriod = .all
    @State private var shareURL: ShareURL?
    @State private var errorMessage: String?
    @State private var showPaywall = false

    var body: some View {
        Form {
            Section("Period") {
                Picker("Period", selection: $period) {
                    ForEach(ExportPeriod.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Revenue") {
                LabeledContent("Total") {
                    Text(revenueText)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }

            Section {
                Button {
                    exportTapped()
                } label: {
                    Label("Share CSV", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Machine CSV: UTF-8, comma-separated, dot decimal \u{2014} opens in any spreadsheet app.")
            }
        }
        .navigationTitle("Export CSV")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareURL) { item in
            ShareSheet(activityItems: [item.url])
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(trigger: .backup)
        }
        .alert("Export failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Derived

    private var revenueText: String {
        let total = store.totalRevenue(period: period)
        let amount = NSDecimalNumber(decimal: total).doubleValue
        return amount.formatted(.currency(code: store.settings.currencyCode))
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    // MARK: - Actions

    private func exportTapped() {
        guard store.isPro else {
            showPaywall = true
            return
        }
        do {
            let url = try store.exportSessionsCSV(period: period)
            shareURL = ShareURL(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Identifiable wrapper so a generated file URL can drive `.sheet(item:)`.
/// File-scoped to avoid colliding with similar wrappers in sibling slices.
private struct ShareURL: Identifiable {
    let id = UUID()
    let url: URL
}
