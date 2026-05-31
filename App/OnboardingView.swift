import SwiftUI

/// Three-page onboarding (spec section 14):
/// 1. Welcome
/// 2. Business info + consent template editor
/// 3. First owner + pet quick add -> sets `hasCompletedOnboarding = true`.
struct OnboardingView: View {
    @EnvironmentObject var store: GroomStore
    @State private var page = 0

    // Page 2 — business + consent template
    @State private var businessInfo = BusinessInfo()
    @State private var consentTemplate = AppSettings.defaultConsentTemplate

    // Page 3 — first owner + pet
    @State private var ownerName = ""
    @State private var ownerPhone = ""
    @State private var petName = ""
    @State private var species: PetSpecies = .dog
    @State private var breed = ""

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                businessPage.tag(1)
                firstPetPage.tag(2)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            footer
                .padding()
        }
        .onAppear {
            consentTemplate = store.settings.consentTemplate.isEmpty
                ? AppSettings.defaultConsentTemplate
                : store.settings.consentTemplate
            businessInfo = store.settings.businessInfo
        }
    }

    // MARK: Pages

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.teal)
            Text("Welcome to GroomCard")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Offline pet cards, consent with signature, and before/after photos — built for the solo and mobile groomer.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .padding()
    }

    private var businessPage: some View {
        Form {
            Section("Your business") {
                TextField("Business name", text: $businessInfo.name)
                TextField("Phone", text: $businessInfo.phone).keyboardType(.phonePad)
                TextField("Email", text: $businessInfo.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }
            Section {
                TextEditor(text: $consentTemplate)
                    .frame(minHeight: 180)
            } header: {
                Text("Consent template")
            } footer: {
                Text("This text appears on every consent. You can edit it later in Settings.")
            }
        }
    }

    private var firstPetPage: some View {
        Form {
            Section("First owner") {
                TextField("Owner name", text: $ownerName)
                TextField("Phone", text: $ownerPhone).keyboardType(.phonePad)
            }
            Section("First pet") {
                TextField("Pet name", text: $petName)
                Picker("Species", selection: $species) {
                    ForEach(PetSpecies.allCases) { species in
                        Label(species.rawValue, systemImage: species.symbolName).tag(species)
                    }
                }
                TextField("Breed", text: $breed)
            }
            Section {
                Text("You can skip this and add pets later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if page > 0 {
                Button("Back") { withAnimation { page -= 1 } }
                    .buttonStyle(.bordered)
            }
            Spacer()
            Button(page < 2 ? "Next" : "Finish") {
                if page < 2 {
                    if page == 1 { persistBusiness() }
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Actions

    private func persistBusiness() {
        store.settings.businessInfo = businessInfo
        store.updateConsentTemplate(consentTemplate)
    }

    private func finish() {
        persistBusiness()

        let trimmedOwner = ownerName.trimmingCharacters(in: .whitespaces)
        if !trimmedOwner.isEmpty {
            var owner = Owner(name: trimmedOwner)
            owner.phone = ownerPhone
            store.add(owner)

            let trimmedPet = petName.trimmingCharacters(in: .whitespaces)
            if !trimmedPet.isEmpty {
                var pet = Pet(name: trimmedPet, ownerId: owner.id)
                pet.species = species
                pet.breed = breed
                _ = store.add(pet)
            }
        }

        store.settings.hasCompletedOnboarding = true
    }
}
