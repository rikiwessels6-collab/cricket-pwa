import Foundation
import UIKit
import SteadyCore

/// Talks to the plate relay (a Cloudflare Worker that holds the Anthropic key).
/// Only the photo, optional size hints and an optional note are sent, and only after the person
/// has turned on "Plate photo estimates" and tapped Analyse.
enum PlateRelay {
    enum Failure: LocalizedError {
        case notConfigured, unauthorised, tooLarge, offline, server(Int), badAnswer
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Plate photos aren't set up in this build yet."
            case .unauthorised: return "The plate service didn't accept this app. It needs updating."
            case .tooLarge: return "That photo is too large. Try again."
            case .offline: return "Couldn't reach the plate service. Check your connection and try again."
            case .server(let code): return "The plate service had a problem (\(code)). Try again in a moment."
            case .badAnswer: return "The plate service sent something unexpected. Try again."
            }
        }
    }

    private static func info(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    static var baseURL: URL? { URL(string: info("PlateRelayURL")) }
    static var isConfigured: Bool { baseURL != nil && !info("PlateRelayToken").isEmpty }

    /// Resize to a long edge of 1568 px and compress until it fits the relay's limit.
    static func prepare(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 1568 ? 1568 / longest : 1
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        var quality = 0.8
        while quality >= 0.3 {
            if let data = resized.jpegData(compressionQuality: quality), data.count * 4 / 3 < 4_300_000 { return data }
            quality -= 0.1
        }
        return nil
    }

    static func estimate(_ request: PlateRequest) async throws -> PlateResult {
        guard isConfigured, let base = baseURL else { throw Failure.notConfigured }
        var req = URLRequest(url: base.appendingPathComponent("v1/plate"), timeoutInterval: 70)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(info("PlateRelayToken"), forHTTPHeaderField: "x-app-token")
        req.httpBody = try JSONEncoder().encode(request)
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) } catch { throw Failure.offline }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: break
        case 401: throw Failure.unauthorised
        case 413: throw Failure.tooLarge
        default: throw Failure.server(status)
        }
        do { return try PlateResult.decode(data) } catch { throw Failure.badAnswer }
    }
}
