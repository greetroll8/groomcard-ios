import StoreKit
import SwiftUI

/// GroomCard Pro paywall (spec 9.4, App Review mitigations in section 19).
///
/// Loads the configured products, drives a purchase, and exposes a mandatory
/// Restore button. Degrades gracefully when no products are configured in App
/// Store Connect. Pro-gated actions present this; base client data stays
/// readable without Pro.
struct Paywall: View {
    @EnvironmentObject private var store: GroomStore
    @Environment(\.dismiss) private var dismiss

    let trigger: PaywallTrigger

    @State private var products: [Product] = []
    @State private var isLoading = true
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var message: String?

    init(trigger: PaywallTrigger = .petLimit) {
        self.trigger = trigger
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    benefits
                    plans
                    restoreButton
                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
            .navigationTitle("GroomCard Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadProducts() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.top, 8)
            Text(headline)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(subhead)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 10) {
            BenefitRow(text: "Unlimited pet profiles")
            BenefitRow(text: "PDF grooming reports and signed consent")
            BenefitRow(text: "CSV revenue export")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var plans: some View {
        if isLoading {
            ProgressView()
                .padding(.vertical, 8)
        } else if products.isEmpty {
            // No StoreKit products configured yet: keep the upgrade path honest.
            Text("Subscriptions are not available right now. Please try again later.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            VStack(spacing: 12) {
                ForEach(products, id: \.id) { product in
                    Button {
                        Task { await purchase(product) }
                    } label: {
                        HStack {
                            Text(product.displayName)
                            Spacer()
                            Text(product.displayPrice).bold()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isPurchasing)
                }
            }
        }
    }

    private var restoreButton: some View {
        Button {
            Task { await restore() }
        } label: {
            if isRestoring {
                ProgressView()
            } else {
                Text("Restore Purchases")
            }
        }
        .disabled(isRestoring)
    }

    // MARK: - StoreKit

    private func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: GroomStore.proProductIDs)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            message = error.localizedDescription
        }
    }

    private func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await store.refreshProEntitlement()
                    if store.isPro { dismiss() }
                }
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        await store.refreshProEntitlement()
        if store.isPro { dismiss() }
    }

    // MARK: - Copy

    private var headline: String {
        switch trigger {
        case .petLimit: return "Add unlimited pets"
        case .pdfExport: return "Share PDF reports"
        case .consentPDF: return "Sign consent as PDF"
        case .backup: return "Back up your data"
        }
    }

    private var subhead: String {
        switch trigger {
        case .petLimit:
            return "You've reached the free pet limit. Upgrade to keep adding pet profiles."
        case .pdfExport:
            return "Generate polished before/after grooming reports to hand to owners."
        case .consentPDF:
            return "Export signed consent forms as PDF for your records and the owner."
        case .backup:
            return "Keep a safe copy of every pet, session, and consent."
        }
    }
}

// NOTE: `PaywallView` is the StoreKit paywall defined in `PaywallView.swift`.
// No typealias here, to avoid an invalid redeclaration of `PaywallView`.

private struct BenefitRow: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .foregroundStyle(.primary)
    }
}
