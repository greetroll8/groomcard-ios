import SwiftUI

/// Settings tab (spec section 8: "consent text, business info, subscription").
///
/// Owns its own `NavigationStack` because the `MainTabView` shell hands this
/// slice the whole tab. Edits flow back through `GroomStore` so the JSON store
/// persists immediately (settings `didSet` saves). Pro state and Restore are
/// surfaced here per the App Review mitigations in spec section 19.
struct SettingsView: View {
    @EnvironmentObject private var store: GroomStore

    @State private var showConsentEditor = false
    @State private var showPaywall = false
    @State private var isRestoring = false

    var body: some View {
        NavigationStack {
            Form {
                proSection
                businessSection
                consentSection
                documentsSection
                exportSection
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showConsentEditor) {
                ConsentTemplateEditor()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(trigger: .backup)
            }
        }
    }

    // MARK: - Pro / subscription

    @ViewBuilder
    private var proSection: some View {
        Section {
            if store.isPro {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GroomCard Pro")
                            .font(.headline)
                        Text("Unlimited pets, PDF reports, and CSV export are unlocked.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.teal)
                }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    Label("Upgrade to GroomCard Pro", systemImage: "pawprint.circle.fill")
                }
                Text("Free plan is limited to \(store.freeLimit) pets. Pro unlocks unlimited pets, PDF reports, and CSV export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await restore() }
            } label: {
                if isRestoring {
                    ProgressView()
                } else {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isRestoring)
        } header: {
            Text("Subscription")
        }
    }

    // MARK: - Business info

    private var businessSection: some View {
        Section {
            TextField("Business name", text: businessBinding(\.name))
                .textInputAutocapitalization(.words)
            TextField("Phone", text: businessBinding(\.phone))
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
            TextField("Email", text: businessBinding(\.email))
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Address", text: businessBinding(\.address), axis: .vertical)
                .lineLimit(1...3)
            TextField("License number", text: businessBinding(\.licenseNumber))
        } header: {
            Text("Business details")
        } footer: {
            Text("Shown on PDF reports and consent forms you hand to owners.")
        }
    }

    // MARK: - Consent

    private var consentSection: some View {
        Section {
            Button {
                showConsentEditor = true
            } label: {
                LabeledContent("Consent template") {
                    Text("v\(store.settings.consentTextVersion)")
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)

            Picker("Re-sign frequency", selection: consentFrequencyBinding) {
                ForEach(ConsentFrequency.allCases) { frequency in
                    Text(frequency.rawValue).tag(frequency)
                }
            }
        } header: {
            Text("Consent")
        } footer: {
            Text("Editing the template bumps its version so existing signed consents keep their original text.")
        }
    }

    // MARK: - Documents / units / language

    private var documentsSection: some View {
        Section {
            Picker("Document language", selection: documentLanguageBinding) {
                ForEach(DocumentLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            Picker("Weight unit", selection: weightUnitBinding) {
                ForEach(WeightUnit.allCases) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            TextField("Currency code", text: currencyBinding)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        } header: {
            Text("Documents & units")
        } footer: {
            Text("Currency uses an ISO code (e.g. USD, EUR, RUB). Amounts are formatted for the device locale.")
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        Section {
            NavigationLink {
                ExportCSVView()
            } label: {
                Label("Export sessions CSV", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Export")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("Pets", value: "\(store.pets.count)")
            LabeledContent("Owners", value: "\(store.owners.count)")
            LabeledContent("Sessions", value: "\(store.sessions.count)")
        } header: {
            Text("Library")
        } footer: {
            Text("GroomCard stores everything offline on this device.")
        }
    }

    // MARK: - Bindings

    private func businessBinding(_ keyPath: WritableKeyPath<BusinessInfo, String>) -> Binding<String> {
        Binding(
            get: { store.settings.businessInfo[keyPath: keyPath] },
            set: { store.settings.businessInfo[keyPath: keyPath] = $0 }
        )
    }

    private var consentFrequencyBinding: Binding<ConsentFrequency> {
        Binding(
            get: { store.settings.consentFrequency },
            set: { store.settings.consentFrequency = $0 }
        )
    }

    private var documentLanguageBinding: Binding<DocumentLanguage> {
        Binding(
            get: { store.settings.documentLanguage },
            set: { store.settings.documentLanguage = $0 }
        )
    }

    private var weightUnitBinding: Binding<WeightUnit> {
        Binding(
            get: { store.settings.weightUnit },
            set: { store.settings.weightUnit = $0 }
        )
    }

    private var currencyBinding: Binding<String> {
        Binding(
            get: { store.settings.currencyCode },
            set: { store.settings.currencyCode = $0.uppercased() }
        )
    }

    // MARK: - Actions

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        await store.refreshProEntitlement()
    }
}

// MARK: - Consent template editor

/// Edits the consent template text. Routes the saved text through
/// `store.updateConsentTemplate(_:)` so the text version bumps only when the
/// content actually changes.
private struct ConsentTemplateEditor: View {
    @EnvironmentObject private var store: GroomStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 280)
                } header: {
                    Text("Consent template")
                } footer: {
                    Text("This text appears on every new consent. Saving changes bumps the version.")
                }
            }
            .navigationTitle("Consent template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateConsentTemplate(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                text = store.settings.consentTemplate.isEmpty
                    ? AppSettings.defaultConsentTemplate
                    : store.settings.consentTemplate
            }
        }
    }
}
