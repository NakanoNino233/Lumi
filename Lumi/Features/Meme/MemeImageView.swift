import SwiftUI
import UIKit
import ImageIO

enum MemeVisual {
    static func thumbnail(_ url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = frame(source, index: 0, size: 220) else { return nil }
        return UIImage(cgImage: image).pngData()
    }
    static func frame(_ source: CGImageSource, index: Int, size: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, index, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: size, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
    }
    static func image(_ data: Data, animate: Bool) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard animate, count > 1 else { return frame(source, index: 0, size: 420).map { UIImage(cgImage: $0) } }
        var frames: [UIImage] = []; var duration = 0.0
        let step = max(1, Int(ceil(Double(count) / 24)))
        for index in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            duration += max(0.03, min(1, (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1))
            if index % step == 0, let frame = frame(source, index: index, size: 320) { frames.append(UIImage(cgImage: frame)) }
        }
        return UIImage.animatedImage(with: frames, duration: max(0.1, duration))
    }
}

struct MemeImageView: UIViewRepresentable {
    let data: Data
    let identity: UUID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @MainActor final class Coordinator { var key = "" }
    @MainActor static let cache: NSCache<NSString, UIImage> = {
        let result = NSCache<NSString, UIImage>(); result.countLimit = 24; result.totalCostLimit = 48_000_000; return result
    }()
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIImageView {
        let image = UIImageView(); image.contentMode = .scaleAspectFit; image.clipsToBounds = true
        image.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        image.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return image
    }
    func updateUIView(_ uiView: UIImageView, context: Context) {
        let key = identity.uuidString + (reduceMotion ? "still" : "animated")
        guard context.coordinator.key != key else { return }; context.coordinator.key = key
        if let image = Self.cache.object(forKey: key as NSString) { uiView.image = image; return }
        let image = MemeVisual.image(data, animate: !reduceMotion)
        uiView.image = image
        if let image { Self.cache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4) * max(1, image.images?.count ?? 1)) }
    }
}

struct MemeBubble: View {
    let meme: SentMeme
    @State private var preview = false
    var body: some View {
        Button { preview = true } label: {
            ZStack { Color.clear; MemeImageView(data: meme.data, identity: meme.id).allowsHitTesting(false) }
                .frame(width: 160, height: 160).contentShape(Rectangle())
        }
            .buttonStyle(.plain).accessibilityLabel(meme.caption).accessibilityIdentifier("meme.message.\(meme.caption)")
            .sheet(isPresented: $preview) {
                NavigationStack {
                    VStack(spacing: 16) { MemeImageView(data: meme.data, identity: meme.id).frame(maxWidth: .infinity, maxHeight: 360); Text(meme.caption).foregroundStyle(.secondary) }.padding()
                        .navigationTitle("表情预览").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { preview = false } } }
                }
            }
    }
}

struct MemeFilePreview: View {
    let meme: Meme
    @State private var data: Data?
    var body: some View {
        VStack { if let data { MemeImageView(data: data, identity: meme.id).frame(width: 240, height: 240) }; Text(meme.caption).padding() }
            .task { data = try? Data(contentsOf: MemeStore.url(meme)) }
    }
}

struct MemeGridTile: View {
    let meme: Meme
    var onSelect: () -> Void
    @State private var thumbnail: Data?
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                if let thumbnail, let image = UIImage(data: thumbnail) { Image(uiImage: image).resizable().scaledToFit().frame(height: 82) }
                else { Image(systemName: "face.smiling").font(.largeTitle).frame(height: 82).foregroundStyle(.secondary) }
                Text(meme.caption).font(.caption).foregroundStyle(.primary).lineLimit(1)
            }.frame(maxWidth: .infinity).padding(8).background(.background, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityIdentifier("meme.pick.\(meme.caption)")
            .contextMenu { Button("发送表情", systemImage: "paperplane", action: onSelect) } preview: { MemeFilePreview(meme: meme) }
            .task(id: meme.fileName) { let url = MemeStore.url(meme); thumbnail = await Task.detached { MemeVisual.thumbnail(url) }.value }
    }
}
