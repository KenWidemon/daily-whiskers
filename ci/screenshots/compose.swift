import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct CaptureIndex: Decodable {
    struct Image: Decodable {
        let file: String
        let width: Int
        let height: Int
        let sha256: String
    }
    let images: [Image]
}

struct Composition {
    let stem: String
    let caption: String
    let tint: NSColor
    let ink: NSColor
}

enum ExportError: Error {
    case invalid(String)
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func readImage(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw ExportError.invalid("Cannot decode \(url.path)")
    }
    return image
}

func bitmap(width: Int, height: Int, draw: () throws -> Void) throws -> CGImage {
    // RGB with an unused fourth byte exports without a PNG alpha channel.
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw ExportError.invalid("Cannot allocate bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    context.interpolationQuality = .high
    try draw()
    guard let result = context.makeImage() else { throw ExportError.invalid("Empty bitmap") }
    return result
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw ExportError.invalid("Cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw ExportError.invalid("PNG export failed") }
    let decoded = try readImage(url)
    guard decoded.width == image.width, decoded.height == image.height,
          [.none, .noneSkipFirst, .noneSkipLast].contains(decoded.alphaInfo) else {
        throw ExportError.invalid("Export dimensions or opacity check failed")
    }
}

func text(_ value: String, in rect: NSRect, font: NSFont, ink: NSColor, tracking: CGFloat = 0) throws {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byClipping
    let attributed = NSAttributedString(string: value, attributes: [
        .font: font, .foregroundColor: ink, .paragraphStyle: paragraph, .kern: tracking
    ])
    let bounds = attributed.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading])
    guard bounds.width <= rect.width + 1, bounds.height <= rect.height + 1 else {
        throw ExportError.invalid("Caption does not fit: \(value)")
    }
    for line in value.split(separator: "\n") {
        let lineWidth = NSAttributedString(string: String(line), attributes: [.font: font, .kern: tracking]).size().width
        guard lineWidth <= rect.width else { throw ExportError.invalid("Caption line too wide") }
    }
    attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
}

func compose(_ source: CGImage, design: Composition, tablet: Bool) throws -> CGImage {
    let width = CGFloat(source.width)
    let height = CGFloat(source.height)
    let screenWidth: CGFloat = tablet ? 1512 : 1020
    let screenHeight = screenWidth * height / width
    let screen = NSRect(x: (width - screenWidth) / 2, y: tablet ? 96 : 92,
                        width: screenWidth, height: screenHeight)
    let headlineSize: CGFloat = tablet ? 122 : 94
    guard let headlineFont = NSFont(name: "Baskerville", size: headlineSize) else {
        throw ExportError.invalid("Baskerville font unavailable")
    }
    return try bitmap(width: source.width, height: source.height) {
        let canvas = NSRect(x: 0, y: 0, width: width, height: height)
        NSGradient(starting: design.tint, ending: color(1, 0.968, 0.924))!.draw(in: canvas, angle: -90)
        try text("DAILY WHISKERS", in: NSRect(x: 80, y: height - 126, width: width - 160, height: 48),
                 font: NSFont.systemFont(ofSize: tablet ? 32 : 26, weight: .medium),
                 ink: design.ink.withAlphaComponent(0.70), tracking: 5)
        try text(design.caption,
                 in: NSRect(x: 80, y: height - (tablet ? 440 : 405), width: width - 160, height: tablet ? 284 : 226),
                 font: headlineFont, ink: design.ink)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = design.ink.withAlphaComponent(0.20)
        shadow.shadowBlurRadius = 38
        shadow.shadowOffset = NSSize(width: 0, height: -16)
        shadow.set()
        design.ink.setFill()
        NSBezierPath(rect: screen).fill()
        NSGraphicsContext.restoreGraphicsState()
        // Draw the complete native screenshot at a uniform scale, without cropping or retouching.
        NSImage(cgImage: source, size: NSSize(width: width, height: height)).draw(in: screen)
        design.ink.withAlphaComponent(0.20).setStroke()
        let border = NSBezierPath(rect: screen.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()
    }
}

func contactSheet(_ urls: [URL], tablet: Bool) throws -> CGImage {
    let width = 1320
    let itemWidth: CGFloat = 396
    let itemHeight: CGFloat = tablet ? 528 : 860.4
    let height = Int(itemHeight) + 180
    return try bitmap(width: width, height: height) {
        color(0.97, 0.955, 0.935).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        try text(tablet ? "iPad compositions / approval review" : "iPhone compositions / approval review",
                 in: NSRect(x: 40, y: height - 65, width: width - 80, height: 35),
                 font: NSFont.systemFont(ofSize: 24, weight: .medium), ink: color(0.2, 0.18, 0.18))
        for (index, url) in urls.enumerated() {
            let image = try readImage(url)
            let rect = NSRect(x: 42 + CGFloat(index) * 420, y: 60, width: itemWidth, height: itemHeight)
            NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).draw(in: rect)
        }
    }
}

do {
    guard CommandLine.arguments.count == 2 else {
        throw ExportError.invalid("Usage: swift ci/screenshots/compose.swift CAPTURE_DIRECTORY")
    }
    let directory = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let index = try JSONDecoder().decode(CaptureIndex.self, from: Data(contentsOf: directory.appendingPathComponent("capture-index.json")))
    let designs = [
        Composition(stem: "01-celestial", caption: "A calm cat moment,\nonce per day.", tint: color(0.947, 0.929, 0.972), ink: color(0.20, 0.16, 0.28)),
        Composition(stem: "02-forest", caption: "A little wonder\nin your day.", tint: color(0.928, 0.953, 0.929), ink: color(0.15, 0.24, 0.18)),
        Composition(stem: "03-cozy", caption: "A few words\nto paws with.", tint: color(0.976, 0.927, 0.889), ink: color(0.29, 0.19, 0.17))
    ]
    let exports = directory.appendingPathComponent("compositions")
    try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
    var records: [[String: Any]] = []
    for family in ["iphone", "ipad"] {
        let output = exports.appendingPathComponent(family)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var urls: [URL] = []
        for design in designs {
            let relative = "\(family)/\(design.stem).png"
            let input = directory.appendingPathComponent(relative)
            let inputData = try Data(contentsOf: input)
            guard let expected = index.images.first(where: { $0.file == relative }), sha256(inputData) == expected.sha256 else {
                throw ExportError.invalid("Source screenshot hash mismatch: \(relative)")
            }
            let source = try readImage(input)
            let dimensions = family == "iphone" ? (1320, 2868) : (2064, 2752)
            guard source.width == dimensions.0, source.height == dimensions.1,
                  source.width == expected.width, source.height == expected.height else {
                throw ExportError.invalid("Unexpected capture dimensions: \(relative)")
            }
            let result = try compose(source, design: design, tablet: family == "ipad")
            let url = output.appendingPathComponent(design.stem + ".png")
            try writePNG(result, to: url)
            records.append(["file": relative, "caption": design.caption.replacingOccurrences(of: "\n", with: " "),
                            "width": result.width, "height": result.height, "has_alpha": false,
                            "source_sha256": expected.sha256, "sha256": sha256(try Data(contentsOf: url))])
            urls.append(url)
            print("Exported \(relative): \(result.width) x \(result.height), opaque sRGB")
        }
        try writePNG(contactSheet(urls, tablet: family == "ipad"), to: exports.appendingPathComponent("\(family)-review.png"))
    }
    let manifest: [String: Any] = ["status": "final-compositions-awaiting-approval", "renderer_sha256": sha256(try Data(contentsOf: URL(fileURLWithPath: #filePath))), "images": records]
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: exports.appendingPathComponent("export-index.json"))
} catch {
    fputs("Screenshot composition failed: \(error)\n", stderr)
    exit(1)
}
