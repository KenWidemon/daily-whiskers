// Decode the finalized simulator recording using the installed Apple frameworks.
// Metadata duration alone cannot prove readable coverage of the interaction.
import AVFoundation
import CoreVideo
import Foundation

do {
    guard CommandLine.arguments.count == 2 else {
        throw NSError(domain: "StillnessVideoProbe", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Expected one recording path"])
    }
    let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
    guard let track = asset.tracks(withMediaType: .video).first else {
        throw NSError(domain: "StillnessVideoProbe", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "No video track"])
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
        throw NSError(domain: "StillnessVideoProbe", code: 3)
    }
    reader.add(output)
    guard reader.startReading() else {
        throw reader.error ?? NSError(domain: "StillnessVideoProbe", code: 4)
    }
    var count = 0
    var first: Double?
    var last: Double?
    var maximumGap = 0.0
    while let frame = autoreleasepool(invoking: { () -> (Double, Bool)? in
        guard let sample = output.copyNextSampleBuffer() else { return nil }
        let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        let pixels = CMSampleBufferGetImageBuffer(sample)
        let readable = pixels.map { CVPixelBufferGetWidth($0) > 0 && CVPixelBufferGetHeight($0) > 0 } ?? false
        return (time, readable)
    }) {
        guard frame.0.isFinite, frame.1, last.map({ frame.0 >= $0 }) ?? true else {
            throw NSError(domain: "StillnessVideoProbe", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Unreadable pixels or invalid frame timeline"])
        }
        if let previous = last { maximumGap = max(maximumGap, frame.0 - previous) }
        if first == nil { first = frame.0 }
        last = frame.0
        count += 1
    }
    guard reader.status == .completed, count > 1, let first, let last else {
        throw reader.error ?? NSError(domain: "StillnessVideoProbe", code: 6)
    }
    let result: [String: Any] = ["decoded_all": true, "frame_count": count,
                               "first_pts": first, "last_pts": last, "max_frame_gap": maximumGap]
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("Video probe failed: \(error)\n".utf8))
    exit(1)
}
