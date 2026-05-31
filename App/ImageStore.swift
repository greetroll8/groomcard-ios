import UIKit

/// Local image persistence for GroomCard.
///
/// Images are stored as JPEGs in `Application Support/GroomImages`.
/// `Store.swift` only ever calls `delete`, but capture/PDF code uses `save` + `load`.
enum ImageStore {
    private static var imagesDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("GroomImages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Persists `image` and returns the generated file name to hand to `store.addPhoto(fileName:)`.
    static func save(_ image: UIImage) throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        let url = imagesDirectory.appendingPathComponent(fileName)
        guard let data = image.jpegData(compressionQuality: 0.82) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: [.atomic])
        return fileName
    }

    static func load(fileName: String?) -> UIImage? {
        guard let fileName else { return nil }
        let url = imagesDirectory.appendingPathComponent(fileName)
        return UIImage(contentsOfFile: url.path)
    }

    static func delete(fileName: String?) {
        guard let fileName else { return }
        let url = imagesDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }
}
