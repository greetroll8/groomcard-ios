import SwiftUI
import UIKit

/// Consent screen (spec 9.2). Renders the resolved consent text and the owner's
/// choices (mat removal, photo release, senior / sedation-free acknowledgements),
/// captures a finger signature, and persists everything through the store.
///
/// Danger gating per spec 15: bite-risk pets show a prominent muzzle warning, and
/// a rabies-expired pet requires an explicit acknowledgement before signing.
struct ConsentView: View {
    @EnvironmentObject private var store: GroomStore
    @Environment(\.dismiss) private var dismiss

    let pet: Pet

    /// Working copy of the consent. Seeded from an existing consent if one was
    /// passed in, otherwise from a fresh draft (which fills resolvedText/version).
    @State private var consent: Consent
    /// True when editing a consent that already exists in the store.
    private let isExisting: Bool

    @State private var showSignature = false
    @State private var rabiesAcknowledged = false
    @State private var paywallTrigger: PaywallTrigger?
    @State private var signatureError: String?
    /// Tracks whether the draft has been inserted into the store yet, so we add
    /// exactly once and update thereafter.
    @State private var didInsert = false

    /// - Parameters:
    ///   - pet: the pet the consent belongs to.
    ///   - consent: an existing consent to edit, or nil to start a new draft.
    init(pet: Pet, consent: Consent? = nil) {
        self.pet = pet
        if let consent {
            _consent = State(initialValue: consent)
            isExisting = true
        } else {
            _consent = State(initialValue: Consent(petId: pet.id))
            isExisting = false
        }
    }

    private var isSenior: Bool {
        pet.behaviorFlags.contains(.senior)
    }

    /// Blocks signing until a rabies-expired pet has been explicitly acknowledged.
    private var canSign: Bool {
        !pet.isRabiesExpired || rabiesAcknowledged
    }

    var body: some View {
        NavigationStack {
            Form {
                warningsSection
                consentTextSection
                choicesSection
                if pet.isRabiesExpired {
                    rabiesAcknowledgeSection
                }
                signatureSection
            }
            .navigationTitle("Consent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                // A draft is created with the latest resolved text/version; if an
                // existing consent somehow lacks text, backfill from the draft.
                if consent.resolvedText.isEmpty {
                    let draft = store.newDraftConsent(forPet: pet.id)
                    consent.resolvedText = draft.resolvedText
                    consent.textVersion = draft.textVersion
                }
            }
            .sheet(isPresented: $showSignature) {
                SignatureCaptureView { image in
                    applySignature(image)
                }
            }
            .sheet(item: $paywallTrigger) { trigger in
                Paywall(trigger: trigger)
            }
            .alert("Couldn't save signature", isPresented: signatureErrorBinding) {
                Button("OK", role: .cancel) { signatureError = nil }
            } message: {
                Text(signatureError ?? "")
            }
        }
    }

    private var signatureErrorBinding: Binding<Bool> {
        Binding(
            get: { signatureError != nil },
            set: { if !$0 { signatureError = nil } }
        )
    }

    // MARK: - Sections

    @ViewBuilder
    private var warningsSection: some View {
        if pet.hasBiteRisk || pet.isRabiesExpired {
            Section {
                if pet.hasBiteRisk {
                    warningRow(
                        symbol: "exclamationmark.triangle.fill",
                        title: "Bite risk",
                        message: "Use a muzzle and handle with caution.",
                        tint: .red
                    )
                }
                if pet.isRabiesExpired {
                    warningRow(
                        symbol: "syringe.fill",
                        title: "Rabies vaccination expired",
                        message: "Confirm the owner accepts the risk below before signing.",
                        tint: .red
                    )
                }
            }
        }
    }

    private var consentTextSection: some View {
        Section("Agreement") {
            ScrollView {
                Text(consent.resolvedText)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }
            .frame(maxHeight: 220)
            LabeledContent("Version", value: consent.textVersion)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var choicesSection: some View {
        Section("Owner choices") {
            Picker("Matted coat", selection: $consent.matRemovalChoice) {
                ForEach(Consent.MatRemovalChoice.allCases) { choice in
                    Text(choice.rawValue.capitalized).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Allow photo publication", isOn: $consent.photoReleaseAllowed)

            Toggle("Acknowledges sedation-free grooming", isOn: $consent.sedationFreeAcknowledged)

            if isSenior {
                Toggle("Accepts senior-pet risks", isOn: $consent.seniorRiskAcknowledged)
            }
        }
    }

    private var rabiesAcknowledgeSection: some View {
        Section {
            Toggle(isOn: $rabiesAcknowledged) {
                Text("Owner confirms the rabies vaccination is expired and accepts the risk.")
                    .font(.subheadline)
            }
            .tint(.red)
        } header: {
            Text("Required acknowledgement")
        }
    }

    @ViewBuilder
    private var signatureSection: some View {
        Section {
            if consent.isSigned {
                signedRow
            } else {
                Button {
                    showSignature = true
                } label: {
                    Label("Sign", systemImage: "signature")
                }
                .disabled(!canSign)

                if !canSign {
                    Text("Acknowledge the expired rabies vaccination to enable signing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if consent.isSigned {
                Text("Signed \(consent.signedAt.formatted(date: .abbreviated, time: .shortened)) · v\(consent.textVersion)")
            }
        }

        if consent.isSigned {
            Section {
                Button {
                    exportPDF()
                } label: {
                    Label("Export consent PDF", systemImage: "doc.text")
                }
            }
        }
    }

    @ViewBuilder
    private var signedRow: some View {
        HStack(spacing: 12) {
            if let image = ImageStore.load(fileName: store.photo(id: consent.signaturePhotoId)?.fileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 64)
                    .frame(maxWidth: 160, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Label("Signed", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Button("Re-sign") {
                    showSignature = true
                }
                .font(.footnote)
            }
            Spacer()
        }
    }

    private func warningRow(symbol: String, title: String, message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    /// Saves the rendered signature image, links it as a `.consentSignature`
    /// photo, stamps the signing time, and persists the consent.
    private func applySignature(_ image: UIImage) {
        // Ensure the consent exists in the store before attaching a photo to its id.
        persistConsent()

        // Drop any previous signature photo on a re-sign.
        if let oldId = consent.signaturePhotoId {
            store.removePhoto(id: oldId)
            consent.signaturePhotoId = nil
        }

        do {
            let fileName = try ImageStore.save(image)
            let photoId = store.addPhoto(
                fileName: fileName,
                refType: .consentSignature,
                refId: consent.id
            )
            consent.signaturePhotoId = photoId
            consent.signedAt = Date()
            store.update(consent)
        } catch {
            // store.saveError is private(set); surface locally instead.
            signatureError = error.localizedDescription
        }
    }

    /// Inserts the consent on first save, or updates it thereafter. Keeps a flag
    /// so we only add once even though signing can happen before/after.
    private func persistConsent() {
        if isExisting || didInsert {
            store.update(consent)
        } else {
            consent = store.add(consent)
            didInsert = true
        }
    }

    private func exportPDF() {
        guard store.isPro else {
            paywallTrigger = .consentPDF
            return
        }
        // Persist any toggle changes before another slice renders the PDF.
        persistConsent()
    }
}
