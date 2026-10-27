import Foundation
import CryptoKit
import ImageIO
import CoreGraphics
import UIKit

/// Immutable content only. Occurrence/date/account information never enters identity.
struct CardSnapshot: Codable, Equatable, Identifiable, Sendable {
    let schemaVersion: Int
    let cardID: String
    let contentRevision: String
    let archetype: String
    let quote: String
    let vibe: String?
    let quoteID: String
    let quoteRevision: String
    let artworkChecksum: String
    let artworkPixelDigest: String
    var id: String { cardID + ":" + contentRevision }

    static func capture(card: DailyCard, artwork: Data, quoteID: String? = nil, quoteRevision: String? = nil) throws -> RetainedCard {
        let pixels = try ArtworkIdentity.pixelDigest(artwork)
        let quoteRevision = quoteRevision ?? ArtworkIdentity.checksum(Data(card.quote.utf8))
        let quoteID = quoteID ?? "legacy:" + card.id
        let revision = revision(cardID: card.id, archetype: card.archetype, quote: card.quote,
                                vibe: card.vibe, quoteID: quoteID, quoteRevision: quoteRevision, pixels: pixels)
        return RetainedCard(snapshot: CardSnapshot(schemaVersion: 1, cardID: card.id,
            contentRevision: revision, archetype: card.archetype, quote: card.quote, vibe: card.vibe,
            quoteID: quoteID, quoteRevision: quoteRevision,
            artworkChecksum: ArtworkIdentity.checksum(artwork), artworkPixelDigest: pixels), artwork: artwork)
    }

    func validate(artwork: Data) throws {
        guard schemaVersion == 1, !cardID.isEmpty,
              ArtworkIdentity.checksum(artwork) == artworkChecksum,
              try ArtworkIdentity.pixelDigest(artwork) == artworkPixelDigest,
              contentRevision == Self.revision(cardID: cardID, archetype: archetype, quote: quote,
                vibe: vibe, quoteID: quoteID, quoteRevision: quoteRevision, pixels: artworkPixelDigest)
        else { throw CardStorageError.unavailable }
    }

    // Versioned length-prefixed UTF-8 fields: nil differs from empty; no locale/JSON ordering.
    private static func revision(cardID: String, archetype: String, quote: String, vibe: String?,
                                 quoteID: String, quoteRevision: String, pixels: String) -> String {
        var bytes = Data("DWCardContent-v1\0".utf8)
        for field in [cardID, archetype, quote, vibe, quoteID, quoteRevision, pixels] {
            if let field {
                let value = Data(field.utf8)
                bytes.append(contentsOf: "\(value.count):".utf8)
                bytes.append(value)
            } else { bytes.append(contentsOf: "-1:".utf8) }
        }
        return ArtworkIdentity.checksum(bytes)
    }
}

struct RetainedCard: Sendable {
    let snapshot: CardSnapshot
    let artwork: Data
}

enum ArtworkIdentity {
    static func checksum(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// Fixed sRGB RGBA8 premultiplied-last surface; dimensions are part of the digest.
    static func pixelDigest(_ bytes: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096,
              (properties[kCGImagePropertyOrientation as String] as? Int ?? 1) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CardStorageError.unavailable }
        return try pixelDigest(image)
    }

    static func pixelDigest(_ image: CGImage) throws -> String {
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= 4096, height <= 4096,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw CardStorageError.unavailable }
        var rgba = Data(count: width * height * 4)
        let rendered = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw CardStorageError.unavailable }
        var digest = SHA256()
        digest.update(data: Data("DWPixels-sRGB-RGBA8-v1:\(width):\(height):".utf8))
        digest.update(data: rgba)
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum BundledCardArtwork {
    static func image(named name: String, bundle: Bundle = .main) -> UIImage? {
        guard let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "CardOriginals") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func bytes(for card: DailyCard, bundle: Bundle = .main) throws -> Data {
        guard let url = bundle.url(forResource: card.imageName, withExtension: "png", subdirectory: "CardOriginals")
        else { throw CardStorageError.unavailable }
        return try Data(contentsOf: url)
    }
}
