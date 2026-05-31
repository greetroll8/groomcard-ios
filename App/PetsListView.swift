import SwiftUI

struct PetsListView: View {
    @EnvironmentObject private var store: GroomStore
    @State private var query = ""
    @State private var filter: PetFilter = .all
    @State private var sort: PetSort = .updated
    @State private var showingEditor = false
    @State private var paywallTrigger: PaywallTrigger?

    var body: some View {
        NavigationStack {
            List {
                let pets = store.filteredPets(search: query, filter: filter, sort: sort)
                if pets.isEmpty {
                    ContentUnavailableView(
                        "No pets",
                        systemImage: "pawprint",
                        description: Text("Add a pet to start a card with breed, coat, flags and consent.")
                    )
                } else {
                    ForEach(pets) { pet in
                        NavigationLink(value: pet) {
                            PetRow(pet: pet)
                        }
                    }
                }
            }
            .navigationTitle("Pets")
            .navigationDestination(for: Pet.self) { pet in
                PetDetailView(pet: pet)
            }
            .searchable(text: $query, prompt: "Search pets or breeds")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(PetFilter.allCases) { value in
                                Text(value.rawValue).tag(value)
                            }
                        }
                        Picker("Sort", selection: $sort) {
                            ForEach(PetSort.allCases) { value in
                                Text(value.rawValue).tag(value)
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if store.isOverFreeLimit {
                            paywallTrigger = .petLimit
                        } else {
                            showingEditor = true
                        }
                    } label: {
                        Label("Add pet", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                PetEditView()
            }
            .sheet(item: $paywallTrigger) { trigger in
                Paywall(trigger: trigger)
            }
        }
    }
}

private struct PetRow: View {
    @EnvironmentObject private var store: GroomStore
    let pet: Pet

    var body: some View {
        HStack(spacing: 12) {
            PhotoThumb(fileName: store.photo(id: pet.mainPhotoId)?.fileName, size: 56)

            VStack(alignment: .leading, spacing: 5) {
                Text(pet.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                FlagBadges(flags: pet.displayFlags, rabiesExpired: pet.isRabiesExpired)
            }

            Spacer(minLength: 4)

            if pet.isRabiesExpired {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if pet.hasBiteRisk {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var subtitle: String {
        let breed = pet.breed.trimmingCharacters(in: .whitespacesAndNewlines)
        if breed.isEmpty {
            return String(localized: "\(pet.species.rawValue)")
        }
        return String(localized: "\(pet.species.rawValue) · \(breed)")
    }
}

// MARK: - Shared row helpers

struct PhotoThumb: View {
    let fileName: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let image = ImageStore.load(fileName: fileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.teal.opacity(0.14))
                    Image(systemName: "pawprint.fill")
                        .foregroundStyle(.teal)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct FlagBadges: View {
    let flags: [BehaviorFlag]
    var rabiesExpired: Bool = false

    var body: some View {
        if flags.isEmpty && !rabiesExpired {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                ForEach(flags) { flag in
                    Label(flag.rawValue, systemImage: flag.symbolName)
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            (flag.isDanger ? Color.red : Color.teal).opacity(0.16),
                            in: Capsule()
                        )
                        .foregroundStyle(flag.isDanger ? .red : .teal)
                }
                if rabiesExpired {
                    Label("Rabies expired", systemImage: "syringe")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.16), in: Capsule())
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
