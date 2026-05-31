import PhotosUI
import SwiftUI
import UIKit

struct PetEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: GroomStore

    private let existingPet: Pet?

    @State private var name: String
    @State private var species: PetSpecies
    @State private var breed: String
    @State private var coatType: CoatType
    @State private var behaviorFlags: Set<BehaviorFlag>
    @State private var allergies: String
    @State private var weight: String
    @State private var weightUnit: WeightUnit
    @State private var hasRabiesExpiry: Bool
    @State private var rabiesExpiry: Date
    @State private var ownerId: UUID?
    @State private var stylePreference: String
    @State private var notes: String
    @State private var mainPhotoId: UUID?

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingAddOwner = false
    @State private var errorMessage: String?

    init(pet: Pet? = nil) {
        existingPet = pet
        _name = State(initialValue: pet?.name ?? "")
        _species = State(initialValue: pet?.species ?? .dog)
        _breed = State(initialValue: pet?.breed ?? "")
        _coatType = State(initialValue: pet?.coatType ?? .unknown)
        _behaviorFlags = State(initialValue: Set(pet?.behaviorFlags ?? []))
        _allergies = State(initialValue: pet?.allergies ?? "")
        _weight = State(initialValue: pet?.weight.map { Self.trimmed($0) } ?? "")
        _weightUnit = State(initialValue: pet?.weightUnit ?? WeightUnit.deviceDefault)
        _hasRabiesExpiry = State(initialValue: pet?.rabiesExpiry != nil)
        _rabiesExpiry = State(initialValue: pet?.rabiesExpiry ?? Date())
        _ownerId = State(initialValue: pet?.ownerId)
        _stylePreference = State(initialValue: pet?.stylePreference ?? "")
        _notes = State(initialValue: pet?.notes ?? "")
        _mainPhotoId = State(initialValue: pet?.mainPhotoId)
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                identitySection
                flagsSection
                healthSection
                ownerSection
                styleSection

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existingPet == nil ? "New pet" : "Edit pet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
            .task(id: selectedPhoto) {
                await importSelectedPhoto()
            }
            .sheet(isPresented: $showingCamera) {
                CameraCaptureView { image in
                    saveCapturedImage(image)
                }
            }
            .sheet(isPresented: $showingAddOwner) {
                AddOwnerSheet { newOwnerId in
                    ownerId = newOwnerId
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ownerId != nil
    }

    // MARK: - Sections

    private var photoSection: some View {
        Section("Photo") {
            HStack(spacing: 12) {
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showingCamera = true
                    } else {
                        errorMessage = "Camera is unavailable on this device."
                    }
                } label: {
                    PhotoActionTile(
                        title: "Take photo",
                        systemImage: "camera",
                        fileName: store.photo(id: mainPhotoId)?.fileName
                    )
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    PhotoActionTile(title: "Choose photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var identitySection: some View {
        Section("Pet") {
            TextField("Name", text: $name)
            Picker("Species", selection: $species) {
                ForEach(PetSpecies.allCases) { value in
                    Label(value.rawValue, systemImage: value.symbolName).tag(value)
                }
            }
            TextField("Breed", text: $breed)
            Picker("Coat type", selection: $coatType) {
                ForEach(CoatType.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
        }
    }

    private var flagsSection: some View {
        Section("Behavior flags") {
            FlagChips(selection: $behaviorFlags)
        }
    }

    private var healthSection: some View {
        Section("Health") {
            TextField("Allergies / health notes", text: $allergies, axis: .vertical)
                .lineLimit(2...5)
            HStack {
                Text("Weight")
                Spacer(minLength: 16)
                TextField("0", text: $weight)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                Picker("Unit", selection: $weightUnit) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 96)
            }
            Toggle("Rabies expiry date", isOn: $hasRabiesExpiry.animation())
            if hasRabiesExpiry {
                DatePicker("Expires", selection: $rabiesExpiry, displayedComponents: .date)
            }
        }
    }

    private var ownerSection: some View {
        Section("Owner") {
            Picker("Owner", selection: $ownerId) {
                Text("Select owner").tag(UUID?.none)
                ForEach(store.owners) { owner in
                    Text(owner.name).tag(UUID?.some(owner.id))
                }
            }
            Button {
                showingAddOwner = true
            } label: {
                Label("Add owner", systemImage: "person.badge.plus")
            }
        }
    }

    private var styleSection: some View {
        Section("Style & notes") {
            TextField("Preferred style", text: $stylePreference, axis: .vertical)
                .lineLimit(1...3)
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    // MARK: - Actions

    private func save() {
        guard let ownerId else {
            errorMessage = "Select an owner first."
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required."
            return
        }

        var pet = existingPet ?? Pet(name: trimmedName, ownerId: ownerId)
        pet.name = trimmedName
        pet.species = species
        pet.breed = breed.trimmingCharacters(in: .whitespacesAndNewlines)
        pet.coatType = coatType
        pet.behaviorFlags = orderedFlags
        pet.allergies = allergies.trimmingCharacters(in: .whitespacesAndNewlines)
        pet.weight = parseWeight(weight)
        pet.weightUnit = weightUnit
        pet.rabiesExpiry = hasRabiesExpiry ? rabiesExpiry : nil
        pet.ownerId = ownerId
        pet.stylePreference = stylePreference.trimmingCharacters(in: .whitespacesAndNewlines)
        pet.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        pet.mainPhotoId = mainPhotoId

        if existingPet == nil {
            guard store.add(pet) else {
                errorMessage = store.saveError ?? "Unable to add pet."
                return
            }
        } else {
            store.update(pet)
        }
        dismiss()
    }

    private var orderedFlags: [BehaviorFlag] {
        BehaviorFlag.allCases.filter { behaviorFlags.contains($0) && $0 != .none }
    }

    private func importSelectedPhoto() async {
        guard let selectedPhoto else { return }
        do {
            guard let data = try await selectedPhoto.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            assignPhoto(image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveCapturedImage(_ image: UIImage) {
        assignPhoto(image)
    }

    private func assignPhoto(_ image: UIImage) {
        do {
            let fileName = try ImageStore.save(image)
            let oldPhotoId = mainPhotoId
            let refId = existingPet?.id ?? UUID()
            let newId = store.addPhoto(fileName: fileName, refType: .pet, refId: refId)
            mainPhotoId = newId
            if let oldPhotoId, oldPhotoId != newId {
                store.removePhoto(id: oldPhotoId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parseWeight(_ input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        if let value = formatter.number(from: trimmed)?.doubleValue {
            return value
        }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private static func trimmed(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(value)
    }
}

// MARK: - Behavior flag chips

private struct FlagChips: View {
    @Binding var selection: Set<BehaviorFlag>

    private var options: [BehaviorFlag] {
        BehaviorFlag.allCases.filter { $0 != .none }
    }

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(options) { flag in
                let isOn = selection.contains(flag)
                Button {
                    if isOn {
                        selection.remove(flag)
                    } else {
                        selection.insert(flag)
                    }
                } label: {
                    Label(flag.rawValue, systemImage: flag.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            chipColor(flag, isOn: isOn),
                            in: Capsule()
                        )
                        .foregroundStyle(isOn ? .white : (flag.isDanger ? Color.red : Color.primary))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func chipColor(_ flag: BehaviorFlag, isOn: Bool) -> Color {
        if isOn {
            return flag.isDanger ? .red : .teal
        }
        return Color(.secondarySystemGroupedBackground)
    }
}

// MARK: - Inline add-owner

private struct AddOwnerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: GroomStore
    let onCreate: (UUID) -> Void

    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Owner") {
                    TextField("Name", text: $name)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("New owner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        var owner = Owner(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        owner.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        owner.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        store.add(owner)
        onCreate(owner.id)
        dismiss()
    }
}

// MARK: - Photo capture helpers

private struct PhotoActionTile: View {
    let title: String
    let systemImage: String
    var fileName: String?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(height: 112)

                if let fileName, let image = ImageStore.load(fileName: fileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.teal)
                }
            }

            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
