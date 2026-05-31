import SwiftUI
import UIKit
import PhotosUI

// MARK: - Camera picker (UIImagePickerController .camera)

/// Wraps UIImagePickerController in `.camera` source mode (spec 11: camera is
/// requested only in the before/after photo context). Returns a single UIImage.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.delegate = context.coordinator
        // Camera is unavailable in the simulator; fall back to the photo library
        // so the flow stays testable rather than crashing.
        controller.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        controller.allowsEditing = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Library picker (PhotosUI -> UIImage)

/// Presents the system photo library via PhotosPicker and resolves the choice
/// into a UIImage (spec 11: Photos is requested when picking from the gallery).
struct LibraryPicker: View {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
            Label("Choose from library", systemImage: "photo.on.rectangle")
        }
        .photosPickerStyle(.inline)
        .photosPickerDisabledCapabilities(.selectionActions)
        .ignoresSafeArea()
        .onChange(of: selection) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        onImage(image)
                        dismiss()
                    }
                } else {
                    await MainActor.run { dismiss() }
                }
            }
        }
    }
}

// MARK: - Shared image source enum

/// Identifiable wrapper so a single `.sheet(item:)` can present either source.
enum PhotoSource: String, Identifiable {
    case camera
    case library

    var id: String { rawValue }
}

// MARK: - CapturePhotoThumb

/// Square rounded thumbnail that loads a stored image by PhotoAsset id off the
/// store. Self-contained (depends only on the data-layer `ImageStore`/`GroomStore`)
/// so the capture slice never collides with other slices' thumbnail views.
struct CapturePhotoThumb: View {
    let photoId: UUID?
    var size: CGFloat = 96
    @EnvironmentObject private var store: GroomStore

    var body: some View {
        let image = ImageStore.load(fileName: store.photo(id: photoId)?.fileName)
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(.secondarySystemBackground)
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }
}

// MARK: - PhotoStrip (editable add/delete grid bound to [UUID])

/// Horizontally scrolling strip of photo thumbnails bound to a `[UUID]` of
/// PhotoAsset ids. Lets the groomer add (camera or library) up to `maxCount`
/// photos and delete existing ones. New images are saved via ImageStore and
/// registered with the store under `refType`/`refId`.
struct PhotoStrip: View {
    let title: String
    @Binding var photoIds: [UUID]
    let refType: PhotoRefType
    let refId: UUID
    var maxCount: Int = 4

    @EnvironmentObject private var store: GroomStore
    @State private var activeSource: PhotoSource?
    @State private var showSourceDialog = false

    private var canAddMore: Bool { photoIds.count < maxCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(photoIds.count)/\(maxCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photoIds, id: \.self) { id in
                        ZStack(alignment: .topTrailing) {
                            CapturePhotoThumb(photoId: id, size: 88)
                            Button {
                                deletePhoto(id: id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white, .black.opacity(0.55))
                                    .padding(4)
                            }
                            .accessibilityLabel("Remove photo")
                        }
                    }

                    if canAddMore {
                        Button {
                            showSourceDialog = true
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                                VStack(spacing: 4) {
                                    Image(systemName: "camera.fill")
                                        .font(.title3)
                                    Text("Add")
                                        .font(.caption)
                                }
                                .foregroundStyle(.tint)
                            }
                            .frame(width: 88, height: 88)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [4]))
                            )
                        }
                        .accessibilityLabel("Add photo")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .confirmationDialog("Add photo", isPresented: $showSourceDialog, titleVisibility: .visible) {
            Button("Take photo") { activeSource = .camera }
            Button("Choose from library") { activeSource = .library }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $activeSource) { source in
            switch source {
            case .camera:
                CameraPicker(onImage: handlePicked)
                    .ignoresSafeArea()
            case .library:
                LibraryPicker(onImage: handlePicked)
            }
        }
    }

    private func handlePicked(_ image: UIImage) {
        guard canAddMore else { return }
        do {
            let fileName = try ImageStore.save(image)
            let id = store.addPhoto(fileName: fileName, refType: refType, refId: refId)
            photoIds.append(id)
        } catch {
            // Saving failed (e.g. disk error); silently ignore so capture never crashes.
        }
    }

    private func deletePhoto(id: UUID) {
        photoIds.removeAll { $0 == id }
        store.removePhoto(id: id)
    }
}

// MARK: - PhotoPickerStrip (alias used by edit forms)

/// Thin alias over `PhotoStrip` matching the name used in session/consent edit
/// forms. Identical behaviour: add (1...maxCount) and delete photos.
struct PhotoPickerStrip: View {
    let title: String
    @Binding var photoIds: [UUID]
    let refType: PhotoRefType
    let refId: UUID
    var maxCount: Int = 4

    var body: some View {
        PhotoStrip(
            title: title,
            photoIds: $photoIds,
            refType: refType,
            refId: refId,
            maxCount: maxCount
        )
    }
}

// MARK: - Bite-risk banner

/// Prominent danger banner surfaced at the top of capture screens when the pet
/// carries the bite-risk flag (spec 15: aggressive animal, muzzle note).
struct BiteRiskBanner: View {
    let pet: Pet?

    var body: some View {
        if let pet, pet.hasBiteRisk {
            HStack(spacing: 10) {
                Image(systemName: BehaviorFlag.bite.symbolName)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bite risk")
                        .font(.subheadline.weight(.bold))
                    Text("Handle with care. Consider a muzzle.")
                        .font(.caption)
                }
                Spacer()
            }
            .padding(12)
            .foregroundStyle(.white)
            .background(Color.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Bite risk. Handle with care. Consider a muzzle.")
        }
    }
}
