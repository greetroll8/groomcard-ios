import SwiftUI
import StoreKit

/// StoreKit 2 paywall (spec 9.4, App Review mitigations in section 19).
///
/// Shown as a sheet via `.sheet(item:)` driven by a `PaywallTrigger`. Loads the
/// monthly / yearly / lifetime products, drives a purchase, and exposes a
/// MANDATORY "Restore Purchases" button. Compiles and degrades gracefully when
/// no products are configured in App Store Connect. A DEBUG-only "Unlock (test)"
/// shortcut helps local testing without a sandbox account.
///
/// Per App Review risk note (section 19): basic pet / owner data viewing always
/// stays free; only adding beyond the free limit and PDF / CSV export are gated.
struct PaywallView: View {
    @EnvironmentObject private var store: GroomStore
    @Environment(\.dismiss) private var dismiss

    let trigger: PaywallTrigger

    @State private var products: [Product] = []
    @State private var selectedProductID: String?
    @State private var isLoadingProducts = true
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
                    reassurance

                    if store.isPro {
                        proActiveBanner
                    } else {
                        plansSection
                        purchaseButton
                    }

                    restoreButton

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    legalCopy

                    #if DEBUG
                    debugTools
                    #endif
                }
                .padding()
            }
            .navigationTitle("GroomCard Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await loadProducts() }
    }

    // MARK: - Trigger copy

    /// Headline varies by what the groomer was trying to do (spec 9.4).
    private var headline: String {
        switch trigger {
        case .petLimit: return "Add unlimited pets"
        case .pdfExport: return "Share client documents"
        case .consentPDF: return "Sign & share consent PDFs"
        case .backup: return "Keep your work backed up"
        }
    }

    private var subhead: String {
        switch trigger {
        case .petLimit:
            return "Free plan limited to \(store.freeLimit) pets. Upgrade to keep adding pets to your book."
        case .pdfExport:
            return "Generate grooming-report PDFs and income CSV exports to hand to every owner."
        case .consentPDF:
            return "Turn signed consents into shareable PDFs with the signature, date and text version."
        case .backup:
            return "iCloud backup is coming in a future update so your cards are never lost."
        }
    }

    private var headerSymbol: String {
        switch trigger {
        case .petLimit: return "pawprint.fill"
        case .pdfExport: return "doc.text.fill"
        case .consentPDF: return "signature"
        case .backup: return "icloud.fill"
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: headerSymbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.teal)
                .accessibilityHidden(true)
            Text(headline)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(subhead)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefitRow("infinity", "Unlimited pets & owners")
            benefitRow("doc.text", "Grooming-report PDFs for owners")
            benefitRow("signature", "Signed consent PDFs")
            benefitRow("tablecells", "Income CSV export")
            benefitRow("lock.open", "One purchase, no account")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func benefitRow(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.teal)
        }
    }

    /// App Review mitigation (section 19): make clear existing data stays visible
    /// without Pro \u{2014} only adding beyond the limit and exporting are gated.
    private var reassurance: some View {
        Text("Your pets, owners, sessions and photos always stay visible \u{2014} Pro only unlocks unlimited pets, PDF reports and CSV export.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var proActiveBanner: some View {
        Label("Pro is active. Thank you!", systemImage: "checkmark.seal.fill")
            .font(.headline)
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var plansSection: some View {
        if isLoadingProducts {
            ProgressView("Loading plans\u{2026}")
                .frame(maxWidth: .infinity)
                .padding()
        } else if products.isEmpty {
            VStack(spacing: 6) {
                Text("Plans are not available right now.")
                    .font(.subheadline)
                Text("Please check your connection and try again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        } else {
            VStack(spacing: 10) {
                ForEach(sortedProducts, id: \.id) { product in
                    planCard(product)
                }
            }
        }
    }

    private func planCard(_ product: Product) -> some View {
        let isSelected = selectedProductID == product.id
        return Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.teal : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(planTitle(product))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if !product.description.isEmpty {
                        Text(product.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(priceLabel(product))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.teal : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var purchaseButton: some View {
        Button {
            Task { await purchaseSelected() }
        } label: {
            HStack {
                if isPurchasing { ProgressView().tint(.white) }
                Text(isPurchasing ? "Processing\u{2026}" : "Continue")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(canPurchase ? Color.teal : Color.gray, in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(.white)
        .disabled(!canPurchase || isPurchasing)
    }

    private var restoreButton: some View {
        Button {
            Task { await restore() }
        } label: {
            HStack(spacing: 6) {
                if isRestoring { ProgressView() }
                Text("Restore Purchases")
            }
        }
        .font(.subheadline)
        .disabled(isRestoring || isPurchasing)
    }

    private var legalCopy: some View {
        VStack(spacing: 6) {
            Text("Payment is charged to your Apple ID. Subscriptions renew automatically unless cancelled at least 24 hours before the period ends. Manage in Settings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Terms of Use", destination: URL(string: "https://quantum.starestategame.com/groomcard/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://quantum.starestategame.com/groomcard/privacy")!)
            }
            .font(.caption2)
        }
        .padding(.top, 8)
    }

    #if DEBUG
    private var debugTools: some View {
        Button("Unlock (test)") {
            store.grantPro()
            message = "Pro granted (debug)."
            dismiss()
        }
        .font(.footnote)
        .foregroundStyle(.orange)
    }
    #endif

    // MARK: - Derived

    /// Stable order following the canonical product-id list (monthly, yearly, lifetime).
    private var sortedProducts: [Product] {
        let order = GroomStore.proProductIDs
        return products.sorted { lhs, rhs in
            let li = order.firstIndex(of: lhs.id) ?? Int.max
            let ri = order.firstIndex(of: rhs.id) ?? Int.max
            return li < ri
        }
    }

    private var canPurchase: Bool {
        !products.isEmpty && selectedProductID != nil
    }

    private func planTitle(_ product: Product) -> String {
        if !product.displayName.isEmpty { return product.displayName }
        if product.id.hasSuffix("monthly") { return "Monthly" }
        if product.id.hasSuffix("yearly") { return "Yearly" }
        if product.id.hasSuffix("lifetime") { return "Lifetime" }
        return product.id
    }

    private func priceLabel(_ product: Product) -> String {
        var label = product.displayPrice
        if let unit = product.subscription?.subscriptionPeriod.unit {
            switch unit {
            case .day: label += " / day"
            case .week: label += " / week"
            case .month: label += " / mo"
            case .year: label += " / yr"
            @unknown default: break
            }
        }
        return label
    }

    // MARK: - StoreKit actions

    private func loadProducts() async {
        isLoadingProducts = true
        do {
            let loaded = try await Product.products(for: GroomStore.proProductIDs)
            products = loaded
            if selectedProductID == nil {
                let order = GroomStore.proProductIDs
                selectedProductID = loaded.sorted {
                    (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max)
                }.first?.id
            }
        } catch {
            products = []
            message = "Could not load plans. \(error.localizedDescription)"
        }
        isLoadingProducts = false
    }

    private func purchaseSelected() async {
        guard let id = selectedProductID,
              let product = products.first(where: { $0.id == id }) else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await store.refreshProEntitlement()
                    message = "Purchase complete."
                    dismiss()
                case .unverified:
                    message = "Purchase could not be verified."
                }
            case .userCancelled:
                break
            case .pending:
                message = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            message = "Purchase failed. \(error.localizedDescription)"
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch {
            // AppStore.sync can throw if the user cancels the auth sheet; fall
            // through to refresh the entitlement from current transactions.
        }
        await store.refreshProEntitlement()
        if store.isPro {
            message = "Purchases restored."
            dismiss()
        } else {
            message = "No purchases found to restore."
        }
    }
}

#Preview {
    PaywallView(trigger: .petLimit)
        .environmentObject(GroomStore())
}
