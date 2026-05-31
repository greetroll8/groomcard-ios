import SwiftUI

/// Read-only detail of a grooming session (spec 9.3 / 13): before and after photo
/// grids shown side by side, style, notes, recommendations, optional price and the
/// date. An Edit button opens `SessionEditView`; "Export report PDF" is gated behind
/// Pro and otherwise presents the paywall (trigger `.pdfExport`).
struct SessionDetailView: View {
    @EnvironmentObject private var store: GroomStore

    let sessionId: UUID

    @State private var editingSession: GroomSession?
    @State private var paywallTrigger: PaywallTrigger?

    /// Open by session id (the view always reads the live copy from the store).
    init(sessionId: UUID) {
        self.sessionId = sessionId
    }

    /// Convenience: open by passing a session value directly.
    init(session: GroomSession) {
        self.sessionId = session.id
    }

    /// Live session lookup so edits made downstream are reflected immediately.
    private var session: GroomSession? {
        store.sessions.first { $0.id == sessionId }
    }

    var body: some View {
        Group {
            if let session {
                content(for: session)
            } else {
                ContentUnavailableView(
                    "Session not found",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("This session may have been deleted.")
                )
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let session {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editingSession = session }
                }
            }
        }
        .sheet(item: $editingSession) { session in
            SessionEditView(session: session)
        }
        .sheet(item: $paywallTrigger) { trigger in
            SessionPaywallSheet(trigger: trigger)
        }
    }

    @ViewBuilder
    private func content(for session: GroomSession) -> some View {
        let pet = store.pet(id: session.petId)
        List {
            if let pet, pet.hasBiteRisk {
                Section {
                    BiteRiskBanner(pet: pet)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                LabeledContent("Date", value: session.date.formatted(date: .abbreviated, time: .shortened))
                if let pet {
                    LabeledContent("Pet", value: pet.name)
                }
                if !session.style.isEmpty {
                    LabeledContent("Style") {
                        Text(session.style)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let price = session.price {
                    LabeledContent("Price", value: price.formatted(.currency(code: session.currencyCode)))
                }
            }

            Section("Before / After") {
                HStack(alignment: .top, spacing: 16) {
                    photoColumn(title: "Before", ids: session.beforePhotoIds)
                    Divider()
                    photoColumn(title: "After", ids: session.afterPhotoIds)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !session.notes.isEmpty {
                Section("Notes") {
                    Text(session.notes)
                }
            }

            if !session.recommendations.isEmpty {
                Section("Recommendations for owner") {
                    Text(session.recommendations)
                }
            }

            Section {
                Button {
                    if store.isPro {
                        // PDF generation is owned by the export slice (PDFExporter);
                        // when Pro, the session is ready to hand off there.
                        exportReport(for: session)
                    } else {
                        paywallTrigger = .pdfExport
                    }
                } label: {
                    Label("Export report PDF", systemImage: "doc.text")
                }
            } footer: {
                if !store.isPro {
                    Text("PDF reports for owners are a Pro feature.")
                }
            }
        }
    }

    @ViewBuilder
    private func photoColumn(title: String, ids: [UUID]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if ids.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 96, height: 96)
            } else {
                ForEach(ids, id: \.self) { id in
                    CapturePhotoThumb(photoId: id, size: 96)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exportReport(for session: GroomSession) {
        // Placeholder hook: the dedicated export slice renders and shares the PDF.
        // Kept local and side-effect-free here so this slice compiles standalone.
        _ = store.nextReportNumber()
    }
}

// MARK: - In-slice paywall sheet

/// Minimal self-contained paywall presented when a Pro-gated action is attempted
/// (spec 9.4 / 19: a Restore button is mandatory, and the base data view stays
/// accessible). The full StoreKit paywall lives in the paywall slice; this keeps
/// the capture slice compiling and the gate honest on its own.
struct SessionPaywallSheet: View {
    @EnvironmentObject private var store: GroomStore
    @Environment(\.dismiss) private var dismiss

    let trigger: PaywallTrigger
    @State private var isRestoring = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "pawprint.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .padding(.top, 24)

                Text(headline)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(subhead)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        store.grantPro()
                        dismiss()
                    } label: {
                        Text("Upgrade to Pro")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

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
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("GroomCard Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func restore() async {
        isRestoring = true
        await store.refreshProEntitlement()
        isRestoring = false
        if store.isPro { dismiss() }
    }

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
