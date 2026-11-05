import UIKit
import Vision

/// Reads text and barcodes from a photo, on the phone. Nothing is sent anywhere.
enum PanelScanner {
    /// Text lines from a photo, top to bottom, with pieces on the same row joined left to right
    /// (so "Protein   6.0 g   20.0 g" comes back as one line).
    static func rows(in image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) { () -> [String] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation)
            guard (try? handler.perform([request])) != nil, let found = request.results else { return [] }
            let pieces = found.compactMap { o -> (y: CGFloat, x: CGFloat, h: CGFloat, text: String)? in
                guard let t = o.topCandidates(1).first?.string else { return nil }
                return (o.boundingBox.midY, o.boundingBox.minX, o.boundingBox.height, t)
            }
            .sorted { $0.y > $1.y }
            var groups: [[(y: CGFloat, x: CGFloat, h: CGFloat, text: String)]] = []
            for p in pieces {
                if var last = groups.last, let first = last.first, abs(first.y - p.y) < max(0.008, first.h * 0.6) {
                    last.append(p)
                    groups[groups.count - 1] = last
                } else {
                    groups.append([p])
                }
            }
            return groups.map { $0.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") }
        }.value
    }

    /// Barcode numbers found in a photo.
    static func barcodes(in image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) { () -> [String] in
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation)
            guard (try? handler.perform([request])) != nil else { return [] }
            return (request.results ?? []).compactMap(\.payloadStringValue)
        }.value
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
