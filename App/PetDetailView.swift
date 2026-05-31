import SwiftUI

struct PetDetailView: View {
    @EnvironmentObject private var store: GroomStore
    @Environment(\.dismiss) private var dismiss
    let pet: Pet

    @State private var showingEditor = false
    @State private var consentTarget: Consent?
    @State private var sessionTarget: GroomSession?
    @State private var showingDeleteConfirm = false

    private var current: Pet {
        store.pet(id: pet.id) ?? pet
    }

    var body: some View {
        List {
            headerSection
            ownerSection
            consentSection
            sessionsSection
            if !current.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !current.allergies.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                notesSection
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $sessionTarget) { session in
            SessionDetailView(session: session)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete pet", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            PetEditView(pet: current)
        }
        .sheet(item: $consentTarget) { consent in
            ConsentView(pet: current, consent: consent)
        }
        .confirmationDialog(
            "Delete this pet?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                store.deletePet(id: current.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also removes its sessions, consents and photos.")
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                PhotoThumb(fileName: store.photo(id: current.mainPhotoId)?.fileName, size: 96)

                VStack(alignment: .leading, spacing: 8) {
                    Text(current.name)
                        .font(.title3.bold())
                    Label(coatLine, systemImage: current.species.symbolName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    FlagBadges(flags: current.displayFlags, rabiesExpired: current.isRabiesExpired)
                    rabiesStatus
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var coatLine: String {
        let breed = current.breed.trimmingCharacters(in: .whitespacesAndNewlines)
        let coat = current.coatType.rawValue
        if breed.isEmpty {
            return String(localized: "\(current.species.rawValue) \u{00B7} \(coat) coat")
        }
        return String(localized: "\(breed) \u{00B7} \(coat) coat")
    }

    @ViewBuilder
    private var rabiesStatus: some View {
        if let expiry = current.rabiesExpiry {
            if current.isRabiesExpired {
                Label("Rabies expired \(expiry.formatted(date: .abbreviated, time: .omitted))", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            } else {
                Label("Rabies valid until \(expiry.formatted(date: .abbreviated, time: .omitted))", systemImage: "checkmark.seal")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var ownerSection: some View {
        Section("Owner") {
            if let owner = store.owner(id: current.ownerId) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(owner.name)
                        .font(.headline)
                    if !owner.phone.isEmpty {
                        Label(owner.phone, systemImage: "phone")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !owner.email.isEmpty {
                        Label(owner.email, systemImage: "envelope")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            } else {
                Text("No owner linked")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var consentSection: some View {
        Section("Consent") {
            if store.needsConsent(forPet: current.id) {
                Label("Consent needed before grooming", systemImage: "signature")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            if let consent = store.latestConsent(forPet: current.id) {
                LabeledContent("Signed", value: consent.isSigned ? consent.signedAt.formatted(date: .abbreviated, time: .omitted) : "Not signed yet")
                LabeledContent("Version", value: consent.textVersion)
                LabeledContent("Mat removal", value: consent.matRemovalChoice.rawValue)
                LabeledContent("Photo release", value: consent.photoReleaseAllowed ? "Allowed" : "Not allowed")
            } else {
                Text("No consent on file")
                    .foregroundStyle(.secondary)
            }

            Button {
                consentTarget = store.newDraftConsent(forPet: current.id)
            } label: {
                Label(store.latestConsent(forPet: current.id) == nil ? "New consent" : "New / re-sign consent", systemImage: "signature")
            }
        }
    }

    @ViewBuilder
    private var sessionsSection: some View {
        Section("Sessions") {
            let sessions = store.sessions(forPet: current.id)
            if sessions.isEmpty {
                Text("No sessions yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions) { session in
                    Button {
                        sessionTarget = session
                    } label: {
                        SessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                sessionTarget = store.newDraftSession(forPet: current.id)
            } label: {
                Label("New session", systemImage: "scissors")
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        Section("Care notes") {
            if !current.allergies.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allergies / health")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(current.allergies)
                }
            }
            if !current.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(current.notes)
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: GroomSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.semibold))
                if !session.style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(session.style)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if session.hasBefore {
                        Label("Before", systemImage: "photo")
                    }
                    if session.hasAfter {
                        Label("After", systemImage: "photo.fill")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.teal)
            }
            Spacer()
            if let price = session.price {
                Text(price.formatted(.currency(code: session.currencyCode)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
