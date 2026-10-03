import Foundation

/// A minimal stand-in for `UniformTypeIdentifiers.UTType`, enough to describe what a file picker should offer.
public struct UTType: Hashable, Sendable {
    public let identifier: String
    /// File name extensions (without the dot) that belong to this type; empty means "any file".
    public let filenameExtensions: [String]

    public init(_ identifier: String, filenameExtensions: [String] = []) {
        self.identifier = identifier
        self.filenameExtensions = filenameExtensions
    }

    public static let item = UTType("public.item")
    public static let data = UTType("public.data")
    public static let content = UTType("public.content")
    public static let text = UTType("public.text", filenameExtensions: ["txt", "text", "md"])
    public static let plainText = UTType("public.plain-text", filenameExtensions: ["txt", "text"])
    public static let json = UTType("public.json", filenameExtensions: ["json"])
    public static let xml = UTType("public.xml", filenameExtensions: ["xml"])
    public static let html = UTType("public.html", filenameExtensions: ["html", "htm"])
    public static let pdf = UTType("com.adobe.pdf", filenameExtensions: ["pdf"])
    public static let image = UTType("public.image", filenameExtensions: ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"])
    public static let png = UTType("public.png", filenameExtensions: ["png"])
    public static let jpeg = UTType("public.jpeg", filenameExtensions: ["jpg", "jpeg"])
    public static let movie = UTType("public.movie", filenameExtensions: ["mp4", "mov", "m4v", "mkv", "webm"])
    public static let audio = UTType("public.audio", filenameExtensions: ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"])
    public static let zip = UTType("public.zip-archive", filenameExtensions: ["zip"])
}

/// Presents the platform's open-file dialog while `isPresented` is true.
public struct FileImporterView<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let isPresented: Binding<Bool>
    public let allowedContentTypes: [UTType]
    public let allowsMultipleSelection: Bool
    public let completion: (Result<[URL], Error>) -> Void

    public var body: Never { fatalError("FileImporterView is a primitive view") }

    /// File name extensions the dialog should offer, or nil when any file is acceptable.
    public var allowedExtensions: [String]? {
        let all = allowedContentTypes
        if all.isEmpty || all.contains(where: { $0.filenameExtensions.isEmpty }) { return nil }
        return all.flatMap(\.filenameExtensions)
    }
}

extension View {
    /// Single-file form.
    public func fileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) -> FileImporterView<Self> {
        FileImporterView(content: self, isPresented: isPresented, allowedContentTypes: allowedContentTypes,
                         allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let first = urls.first { onCompletion(.success(first)) }
                else { onCompletion(.failure(CocoaError(.userCancelled))) }
            case .failure(let error): onCompletion(.failure(error))
            }
        }
    }

    public func fileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool,
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) -> FileImporterView<Self> {
        FileImporterView(content: self, isPresented: isPresented, allowedContentTypes: allowedContentTypes,
                         allowsMultipleSelection: allowsMultipleSelection, completion: onCompletion)
    }
}
