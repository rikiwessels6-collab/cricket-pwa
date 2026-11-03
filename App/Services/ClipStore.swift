import Foundation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Your own demo clips, kept inside the app on this phone only (one per exercise).
/// Nothing is uploaded, and the files go with the app if it's deleted.
enum ClipStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return dir
    }

    private static func fileName(_ exerciseId: String) -> String {
        exerciseId.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" } + ".mov"
    }

    static func url(for exerciseId: String) -> URL? {
        let u = directory.appendingPathComponent(fileName(exerciseId))
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    static func save(_ source: URL, for exerciseId: String) throws {
        let dest = directory.appendingPathComponent(fileName(exerciseId))
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: source, to: dest)
    }

    static func delete(for exerciseId: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName(exerciseId)))
    }
}

/// A video picked from the photo library, copied to a temporary file so it can be moved into the store.
struct PickedVideo: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedVideo(url: dest)
        }
    }
}
