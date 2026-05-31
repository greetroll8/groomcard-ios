import SwiftUI

/// Create or edit a grooming session (spec 9.3): date, style, before/after photos
/// (1...4 each), notes, recommendations, and an optional price with currency.
///
/// New sessions are persisted up front (so photo asset refIds are stable while the
/// user attaches before/after shots), then patched on Save. The bite-risk banner is
/// surfaced at the top so the groomer sees the warning while documenting the work.
struct SessionEditView: View {
    @EnvironmentObject private var store: GroomStore
    @Environment(\.dismiss) private var dismiss

    /// The pet this session belongs to; drives the bite-risk banner and currency.
    let petId: UUID
    /// True for a brand-new session that must be inserted before editing photos.
    private let isNew: Bool

    @State private var session: GroomSession
    @State private var priceText: String

    /// Edit an existing session.
    init(session: GroomSession) {
        self.petId = session.petId
        self.isNew = false
        _session = State(initialValue: session)
        _priceText = State(initialValue: Self.priceString(session.price))
    }

    /// Create a new session for a pet, seeded with repeat defaults.
    /// `seed` should come from `store.newDraftSession(forPet:)`.
    init(newSessionFor petId: UUID, seed: GroomSession) {
        self.petId = petId
        self.isNew = true
        _session = State(initialValue: seed)
        _priceText = State(initialValue: Self.priceString(seed.price))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let pet = store.pet(id: petId), pet.hasBiteRisk {
                    Section {
                        BiteRiskBanner(pet: pet)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section("When") {
                    DatePicker(
                        "Date",
                        selection: $session.date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Style") {
                    TextField("Style / length by zone", text: $session.style, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Before") {
                    PhotoPickerStrip(
                        title: "Before photos",
                        photoIds: $session.beforePhotoIds,
                        refType: .sessionBefore,
                        refId: session.id,
                        maxCount: 4
                    )
                }

                Section("After") {
                    PhotoPickerStrip(
                        title: "After photos",
                        photoIds: $session.afterPhotoIds,
                        refType: .sessionAfter,
                        refId: session.id,
                        maxCount: 4
                    )
                }

                Section("Notes") {
                    TextField("Session notes", text: $session.notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Recommendations for owner") {
                    TextField("Recommendations", text: $session.recommendations, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Price (optional)") {
                    HStack {
                        Text(session.currencyCode)
                            .foregroundStyle(.secondary)
                        TextField("0", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle(isNew ? "New Session" : "Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        cancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
            .onAppear {
                // Persist the draft so attached photos reference a real session id.
                if isNew, store.sessions.first(where: { $0.id == session.id }) == nil {
                    session = store.add(session)
                }
            }
        }
    }

    private func save() {
        session.price = Self.parsePrice(priceText)
        store.update(session)
        dismiss()
    }

    private func cancel() {
        // A new session was inserted on appear; discard it (and its photos) on cancel.
        if isNew {
            store.deleteSession(id: session.id)
        }
        dismiss()
    }

    // MARK: - Price parsing / formatting

    private static func priceString(_ price: Decimal?) -> String {
        guard let price else { return "" }
        return NSDecimalNumber(decimal: price).stringValue
    }

    private static func parsePrice(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Accept both comma and dot decimal separators from the keypad.
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        let value = NSDecimalNumber(string: normalized)
        return value == .notANumber ? nil : value.decimalValue
    }
}
