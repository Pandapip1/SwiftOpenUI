#if !BACKEND_GTK
import Foundation
import SwiftOpenUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if canImport(WebKit) && (os(macOS) || os(iOS) || os(visionOS))
import WebKit
#endif

/// A picture of a tab's page as it was last shown, for its overview card.
struct BrowserTabSnapshot {
    let image: CGImage
    let scale: CGFloat
}

/// Takes pictures of the tab area as it is on screen.
///
/// The overview shows these instead of rendering every page a second time. A
/// second copy of a page costs a full render per tab and, for a web page,
/// takes its web view away from the tab, which reloads it. GTK's native tab
/// overview draws its own thumbnails, so this is Apple-only.
@MainActor
final class BrowserTabSnapshotter {
    /// Cards are at most a few hundred points wide; larger pictures only
    /// cost memory.
    private static let maximumPixelWidth: CGFloat = 720

    fileprivate weak var probe: BrowserTabSnapshotProbe.PlatformView?

    #if canImport(WebKit) && (os(macOS) || os(iOS) || os(visionOS))
    private var registries: [UUID: WebViewSnapshotRegistry] = [:]

    /// Where the web views of one tab register, so its picture includes them.
    func registry(for tab: UUID) -> WebViewSnapshotRegistry {
        if let registry = registries[tab] { return registry }
        let registry = WebViewSnapshotRegistry()
        registries[tab] = registry
        return registry
    }
    #endif

    /// Drops what belongs to tabs that no longer exist.
    func retain(only tabs: Set<UUID>) {
        #if canImport(WebKit) && (os(macOS) || os(iOS) || os(visionOS))
        registries = registries.filter { tabs.contains($0.key) }
        #endif
    }

    /// A picture of the tab area, which shows `tab`.
    func capture(tab: UUID) async -> BrowserTabSnapshot? {
        #if canImport(UIKit)
        guard let view = probe, let window = view.window, view.bounds.width >= 1, view.bounds.height >= 1 else {
            return nil
        }
        // Drawing the window's hierarchy includes web and video content.
        let rect = view.convert(view.bounds, to: window)
        let format = UIGraphicsImageRendererFormat(for: window.traitCollection)
        format.scale = min(format.scale, Self.maximumPixelWidth / rect.width)
        let image = UIGraphicsImageRenderer(bounds: rect, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return image.cgImage.map { BrowserTabSnapshot(image: $0, scale: image.scale) }
        #elseif canImport(AppKit)
        guard let view = probe, let window = view.window, let contentView = window.contentView else { return nil }
        let rect = view.convert(view.bounds, to: contentView)
        guard rect.width >= 1, rect.height >= 1,
              let representation = contentView.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        contentView.cacheDisplay(in: rect, to: representation)
        guard let base = representation.cgImage else { return nil }
        let scale = min(CGFloat(representation.pixelsWide) / rect.width, Self.maximumPixelWidth / rect.width)
        let pixelWidth = Int((rect.width * scale).rounded()), pixelHeight = Int((rect.height * scale).rounded())
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(base, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        // A window capture shows web views blank (their content renders in
        // another process), so each draws its own snapshot over its frame.
        for webView in registry(for: tab).webViews where webView.window === window && !webView.isHiddenOrHasHiddenAncestor {
            guard let picture = try? await webView.takeSnapshot(configuration: nil),
                  let image = picture.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            // In the probe's (unflipped) coordinates, as the context's.
            let frame = webView.convert(webView.bounds, to: view)
            context.draw(image, in: CGRect(x: frame.minX * scale, y: frame.minY * scale,
                                           width: frame.width * scale, height: frame.height * scale))
        }
        return context.makeImage().map { BrowserTabSnapshot(image: $0, scale: scale) }
        #else
        return nil
        #endif
    }
}

/// An invisible view spanning the tab area, which the snapshotter captures.
struct BrowserTabSnapshotProbe {
    let snapshotter: BrowserTabSnapshotter

    #if canImport(UIKit)
    final class PlatformView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }
    }
    #elseif canImport(AppKit)
    final class PlatformView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    #endif
}

#if canImport(UIKit)
extension BrowserTabSnapshotProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> PlatformView {
        let view = PlatformView()
        snapshotter.probe = view
        return view
    }

    func updateUIView(_ view: PlatformView, context: Context) { snapshotter.probe = view }
}
#elseif canImport(AppKit)
extension BrowserTabSnapshotProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> PlatformView {
        let view = PlatformView()
        snapshotter.probe = view
        return view
    }

    func updateNSView(_ view: PlatformView, context: Context) { snapshotter.probe = view }
}
#endif

extension View {
    /// Registers the tab's web views with the snapshotter, so its picture
    /// includes their content.
    @ViewBuilder
    func browserTabWebViewRegistry(_ snapshotter: BrowserTabSnapshotter, tab: UUID) -> some View {
        #if canImport(WebKit) && (os(macOS) || os(iOS) || os(visionOS))
        environment(\.webViewSnapshotRegistry, snapshotter.registry(for: tab))
        #else
        self
        #endif
    }
}

/// A card's picture of its tab: the last snapshot, or a plain placeholder for
/// a tab not shown since launch.
struct BrowserTabSnapshotView: View {
    let snapshot: BrowserTabSnapshot?

    var body: some View {
        if let snapshot {
            Image(decorative: snapshot.image, scale: snapshot.scale)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.08))
                .overlay {
                    Image(systemName: "square.on.square")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
        }
    }
}
#endif
