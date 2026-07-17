//
//  AnimatedImageView.swift
//  SuStash
//
//  Plays GIF data via UIImageView (SwiftUI has no native animated-image
//  view). Frames are decoded once with ImageIO; UIImageView handles playback.
//

import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AnimatedImageView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        // Let SwiftUI's frame win over the image's intrinsic size.
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.image = UIImage.animatedGIF(from: data)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        // Data is immutable per item; nothing to update.
    }
}

extension UIImage {
    /// Builds an animating UIImage from GIF data. Returns a static image
    /// for single-frame data, nil for non-image data.
    static func animatedGIF(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else { return UIImage(data: data) }

        var frames: [UIImage] = []
        var totalDuration: TimeInterval = 0
        frames.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            totalDuration += frameDuration(source: source, index: index)
        }

        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: max(totalDuration, 0.1))
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let unclamped = gifProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
        let clamped = gifProperties?[kCGImagePropertyGIFDelayTime] as? TimeInterval
        let duration = unclamped ?? clamped ?? 0.1
        // Browsers treat near-zero delays as 100ms; match that.
        return duration < 0.02 ? 0.1 : duration
    }
}
