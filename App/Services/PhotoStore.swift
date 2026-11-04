import Foundation
import UIKit
import ImageIO

/// Progress photos are kept as files inside the app, locked whenever the phone is locked.
/// They are never added to your Photos library and never sent anywhere.
enum PhotoStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ProgressPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.complete])
        return dir
    }

    private static func url(_ fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// Shrinks a photo to at most 1600 px on its long edge (enough to compare, small to keep).
    private static func prepared(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 1600 ? 1600 / longest : 1
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.82)
    }

    /// Saves a photo and returns its file name.
    static func save(_ image: UIImage) throws -> String {
        guard let data = prepared(image) else { throw CocoaError(.fileWriteUnknown) }
        let name = UUID().uuidString + ".jpg"
        try data.write(to: url(name), options: [.atomic, .completeFileProtection])
        return name
    }

    static func load(_ fileName: String) -> UIImage? {
        UIImage(contentsOfFile: url(fileName).path)
    }

    /// A small version for lists, so a long history stays quick.
    static func thumbnail(_ fileName: String, maxPixel: Int = 360) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url(fileName) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(fileName))
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
