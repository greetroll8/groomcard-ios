import SwiftUI

/// Four-tab shell matching the spec Information Architecture (section 8).
///
/// Pets and Settings tabs are owned by sibling slices (`PetsListView`,
/// `SettingsView`) which manage their own `NavigationStack`. The shell owns the
/// Today and Owners tab roots and wraps them in their own stacks.
struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                TodayView()
            }
            .tabItem {
                Label("Today", systemImage: "calendar.badge.clock")
            }

            PetsListView()
                .tabItem {
                    Label("Pets", systemImage: "pawprint")
                }

            NavigationStack {
                OwnersView()
            }
            .tabItem {
                Label("Owners", systemImage: "person.2")
            }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

// MARK: - Today

/// Sessions logged today, expired-rabies warnings, and a quick "New session"
/// entry point (spec section 8: "Today — sessions of the day, quick start").
struct TodayView: View {
    @EnvironmentObject private var store: GroomStore
    @State private var pickPetForSession = false
    @State private var newSessionPet: Pet?

    var body: some View {
        List {
            if !store.expiredRabiesPets.isEmpty {
                Section {
                    ForEach(store.expiredRabiesPets) { pet in
                        NavigationLink(value: pet) {
                            RabiesWarningRow(pet: pet)
                        }
                    }
                } header: {
                    Label("Rabies vaccination expired", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section("Today") {
                if store.todaySessions.isEmpty {
                    EmptyStateView(
                        systemImage: "calendar.badge.clock",
                        title: "No sessions today",
                        message: "Start a new grooming session to log before/after photos and notes."
                    )
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(store.todaySessions) { session in
                        NavigationLink(value: session) {
                            TodaySessionRow(session: session)
                        }
                    }
                }
            }
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    pickPetForSession = true
                } label: {
                    Label("New session", systemImage: "plus")
                }
                .disabled(store.pets.isEmpty)
            }
        }
        .navigationDestination(for: GroomSession.self) { session in
            SessionDetailView(sessionId: session.id)
        }
        .navigationDestination(for: Pet.self) { pet in
            PetDetailView(pet: pet)
        }
        .sheet(isPresented: $pickPetForSession) {
            PetPickerView { pet in
                pickPetForSession = false
                newSessionPet = pet
            }
        }
        .sheet(item: $newSessionPet) { pet in
            SessionEditView(newSessionFor: pet.id, seed: store.newDraftSession(forPet: pet.id))
        }
    }
}

private struct TodaySessionRow: View {
    @EnvironmentObject private var store: GroomStore
    let session: GroomSession

    var body: some View {
        HStack(spacing: 12) {
            PhotoThumb(fileName: store.photo(id: session.beforePhotoIds.first)?.fileName, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.pet(id: session.petId)?.name ?? "Pet")
                    .font(.headline)
                if !session.style.isEmpty {
                    Text(session.style)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    if session.hasBefore {
                        Image(systemName: "photo").font(.caption2).foregroundStyle(.secondary)
                    }
                    if session.hasAfter {
                        Image(systemName: "checkmark.seal").font(.caption2).foregroundStyle(.teal)
                    }
                }
                Text(session.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RabiesWarningRow: View {
    let pet: Pet

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "syringe")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(pet.name).font(.headline)
                Text("Rabies vaccination expired")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
            RabiesExpiryBadge(expiry: pet.rabiesExpiry)
        }
    }
}

/// Lightweight pet picker used to seed a new session from the Today tab.
struct PetPickerView: View {
    @EnvironmentObject private var store: GroomStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    let onSelect: (Pet) -> Void

    var body: some View {
        NavigationStack {
            List {
                let pets = store.filteredPets(search: search, filter: .all, sort: .name)
                if pets.isEmpty {
                    EmptyStateView(
                        systemImage: "pawprint",
                        title: "No pets yet",
                        message: "Add a pet first, then start a session."
                    )
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(pets) { pet in
                        Button {
                            onSelect(pet)
                        } label: {
                            HStack(spacing: 12) {
                                PhotoThumb(fileName: store.photo(id: pet.mainPhotoId)?.fileName, size: 40)
                                VStack(alignment: .leading) {
                                    Text(pet.name).font(.headline)
                                    Text(store.owner(id: pet.ownerId)?.name ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                ForEach(pet.displayFlags.filter(\.isDanger)) { flag in
                                    FlagBadge(flag: flag)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Choose pet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Owners

/// Owners tab (spec section 8). Lists owners with contact + pet count and links
/// to a detail screen grouping the owner's pets (spec section 15: multiple pets
/// per owner are grouped under the owner).
struct OwnersView: View {
    @EnvironmentObject private var store: GroomStore
    @State private var search = ""
    @State private var showAddOwner = false

    var body: some View {
        List {
            let owners = store.filteredOwners(search: search)
            if store.owners.isEmpty {
                ContentUnavailableView(
                    "No owners",
                    systemImage: "person.2",
                    description: Text("Add an owner to group their pets and store contact details.")
                )
            } else {
                ForEach(owners) { owner in
                    NavigationLink(value: owner) {
                        OwnerRow(owner: owner)
                    }
                }
            }
        }
        .navigationTitle("Owners")
        .searchable(text: $search, prompt: "Search owners")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddOwner = true
                } label: {
                    Label("Add owner", systemImage: "plus")
                }
            }
        }
        .navigationDestination(for: Owner.self) { owner in
            OwnerDetailView(owner: owner)
        }
        .navigationDestination(for: Pet.self) { pet in
            PetDetailView(pet: pet)
        }
        .sheet(isPresented: $showAddOwner) {
            OwnerEditView(owner: nil)
        }
    }
}

private struct OwnerRow: View {
    @EnvironmentObject private var store: GroomStore
    let owner: Owner

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(owner.name).font(.headline)
            let petCount = store.pets(forOwner: owner.id).count
            HStack(spacing: 10) {
                if !owner.phone.isEmpty {
                    Label(owner.phone, systemImage: "phone")
                }
                Text("\(petCount) pet\(petCount == 1 ? "" : "s")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct OwnerDetailView: View {
    @EnvironmentObject private var store: GroomStore
    @Environment(\.dismiss) private var dismiss
    let owner: Owner

    @State private var showEditor = false
    @State private var showAddPet = false
    @State private var paywallTrigger: PaywallTrigger?
    @State private var showDeleteConfirm = false

    private var current: Owner { store.owner(id: owner.id) ?? owner }

    var body: some View {
        let owner = current
        List {
            Section("Contact") {
                if !owner.phone.isEmpty { LabeledContent("Phone", value: owner.phone) }
                if !owner.email.isEmpty { LabeledContent("Email", value: owner.email) }
                if owner.phone.isEmpty && owner.email.isEmpty {
                    Text("No contact details").foregroundStyle(.secondary)
                }
                if !owner.notes.isEmpty {
                    Text(owner.notes)
                }
            }

            Section("Pets") {
                let pets = store.pets(forOwner: owner.id)
                if pets.isEmpty {
                    Text("No pets").foregroundStyle(.secondary)
                } else {
                    ForEach(pets) { pet in
                        NavigationLink(value: pet) {
                            HStack(spacing: 10) {
                                PhotoThumb(fileName: store.photo(id: pet.mainPhotoId)?.fileName, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pet.name)
                                    if !pet.breed.isEmpty {
                                        Text(pet.breed).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                FlagBadges(flags: pet.displayFlags.filter(\.isDanger), rabiesExpired: pet.isRabiesExpired)
                            }
                        }
                    }
                }
                Button {
                    if store.isOverFreeLimit {
                        paywallTrigger = .petLimit
                    } else {
                        showAddPet = true
                    }
                } label: {
                    Label("Add pet", systemImage: "pawprint")
                }
            }
        }
        .navigationTitle(owner.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEditor = true } label: {
                        Label("Edit owner", systemImage: "pencil")
                    }
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Delete owner", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditor) { OwnerEditView(owner: owner) }
        .sheet(isPresented: $showAddPet) { PetEditView() }
        .sheet(item: $paywallTrigger) { trigger in
            Paywall(trigger: trigger)
        }
        .confirmationDialog(
            "Delete this owner?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                store.deleteOwner(id: owner.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also removes the owner's pets, sessions and consents.")
        }
    }
}

/// Add / edit an owner. Self-contained so the Owners tab works standalone.
struct OwnerEditView: View {
    @EnvironmentObject private var store: GroomStore
    @Environment(\.dismiss) private var dismiss
    let owner: Owner?

    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var notes = ""

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(owner == nil ? "New owner" : "Edit owner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!isValid) }
            }
            .onAppear {
                if let owner {
                    name = owner.name
                    phone = owner.phone
                    email = owner.email
                    notes = owner.notes
                }
            }
        }
    }

    private func save() {
        var working = owner ?? Owner(name: name)
        working.name = name.trimmingCharacters(in: .whitespaces)
        working.phone = phone
        working.email = email
        working.notes = notes
        if owner == nil { store.add(working) } else { store.update(working) }
        dismiss()
    }
}
