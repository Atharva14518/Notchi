import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ProviderBox: @unchecked Sendable { let value: NSItemProvider; init(_ value: NSItemProvider) { self.value = value } }
struct PromiseBox: @unchecked Sendable { let value: NSFilePromiseReceiver; let count: Int }
enum DropPayload: Sendable {
    case file(URL), web(URL), text(String), bytes(Data, String, String?), promise(PromiseBox)
}
struct DropImportResult: Sendable { var urls: [URL] = []; var errors: [String] = [] }

@MainActor
enum PasteboardDrop {
    static let registeredTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL, .string, .png, .tiff] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    static func read(_ pasteboard: NSPasteboard) -> [DropPayload] {
        let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !files.isEmpty { return files.map(DropPayload.file) }
        let promises = (pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver]) ?? []
        if !promises.isEmpty { return promises.map { .promise(PromiseBox(value: $0, count: max(1, $0.fileNames.count))) } }
        return (pasteboard.pasteboardItems ?? []).compactMap { item in
            if let string = item.string(forType: .fileURL), let url = URL(string: string), url.isFileURL { return .file(url) }
            if let string = item.string(forType: .URL), let url = URL(string: string), url.scheme != nil {
                return url.isFileURL ? .file(url) : .web(url)
            }
            for type in [NSPasteboard.PasteboardType.png, .tiff] {
                if let data = item.data(forType: type) { return .bytes(data, type.rawValue, nil) }
            }
            if let text = item.string(forType: .string), !text.isEmpty { return .text(text) }
            return nil
        }
    }
}

/// Async callback bridge with a deadline; late provider callbacks cannot resume twice.
private final class CallbackGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            self.finish(.failure(ActionError.failed(String(localized: "That app didn’t finish the drop. Please try again."))))
        }
    }
    func finish(_ result: Swift.Result<Value, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

private final class PromiseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var urls: [URL] = []
    private var firstError: Error?
    private let gate: CallbackGate<[URL]>
    init(count: Int, gate: CallbackGate<[URL]>) { remaining = count; self.gate = gate }
    func receive(_ url: URL, _ error: Error?) {
        lock.lock()
        if let error { firstError = firstError ?? error } else { urls.append(url) }
        remaining -= 1
        let done = remaining == 0
        let result: Swift.Result<[URL], Error> = urls.isEmpty && firstError != nil ? .failure(firstError!) : .success(urls)
        lock.unlock()
        if done { gate.finish(result) }
    }
}

actor DropImporter {
    private let root: URL
    init(root: URL = ShelfLocations.imports) { self.root = root }
    nonisolated static func supports(_ provider: NSItemProvider) -> Bool {
        provider.registeredTypeIdentifiers.contains { id in
            guard let type = UTType(id) else { return false }
            return type.conforms(to: .fileURL) || type.conforms(to: .url) || type.conforms(to: .image)
                || type.conforms(to: .text) || type.conforms(to: .data)
        }
    }

    func resolve(payloads: [DropPayload]) async -> DropImportResult {
        var result = DropImportResult()
        for payload in payloads {
            do { result.urls += try await resolve(payload) }
            catch { result.errors.append(error.localizedDescription) }
        }
        return result
    }
    func resolve(providers: [ProviderBox]) async -> DropImportResult {
        var result = DropImportResult()
        for box in providers {
            do { result.urls += try await resolve(box.value) }
            catch { result.errors.append(error.localizedDescription) }
        }
        return result
    }

    private func resolve(_ payload: DropPayload) async throws -> [URL] {
        switch payload {
        case .file(let url): return [url.standardizedFileURL] // Never copy an existing file/folder.
        case .web(let url):
            let data = try PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0)
            return [try write(data, name: (url.host ?? "Link") + ".webloc")]
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.contains(where: { $0.isWhitespace }), let url = URL(string: trimmed), url.scheme != nil {
                return try await resolve(url.isFileURL ? .file(url) : .web(url))
            }
            return [try write(Data(text.utf8), name: "Dropped text.txt")]
        case .bytes(let data, let identifier, let suggestedName):
            var type = UTType(identifier) ?? .data
            if let source = CGImageSourceCreateWithData(data as CFData, nil), let id = CGImageSourceGetType(source) {
                type = UTType(id as String) ?? type
            }
            let ext = type.preferredFilenameExtension ?? "bin"
            return [try write(data, name: Self.safeName(suggestedName ?? String(localized: "Dropped image"), extension: ext))]
        case .promise(let box):
            let folder = try ShelfLocations.importFolder(root: root)
            return try await withCheckedThrowingContinuation { continuation in
                let collector = PromiseCollector(count: box.count, gate: CallbackGate(continuation))
                let queue = OperationQueue()
                queue.qualityOfService = .userInitiated
                box.value.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue) {
                    collector.receive($0, $1)
                }
            }
        }
    }

    private func resolve(_ provider: NSItemProvider) async throws -> [URL] {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL = try await withCheckedThrowingContinuation { continuation in
                let gate = CallbackGate(continuation)
                provider.loadObject(ofClass: NSURL.self) { object, error in
                    if let url = object as? URL { gate.finish(.success(url)) }
                    else { gate.finish(.failure(error ?? ActionError.failed(String(localized: "Couldn’t read that file URL.")))) }
                }
            }
            return [url.standardizedFileURL]
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            let data = try await data(from: provider, type: UTType.url.identifier)
            guard let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters),
                  let url = URL(string: string) else { throw ActionError.failed(String(localized: "Couldn’t read that link.")) }
            return try await resolve(url.isFileURL ? .file(url) : .web(url))
        }
        if let id = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
            return try await resolve(.bytes(try await data(from: provider, type: id), id, provider.suggestedName))
        }
        if provider.canLoadObject(ofClass: NSString.self) {
            let text: String = try await withCheckedThrowingContinuation { continuation in
                let gate = CallbackGate(continuation)
                provider.loadObject(ofClass: NSString.self) { object, error in
                    if let text = object as? String { gate.finish(.success(text)) }
                    else { gate.finish(.failure(error ?? ActionError.failed(String(localized: "Couldn’t read that text.")))) }
                }
            }
            return try await resolve(.text(text))
        }
        guard let id = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .data) == true }) else {
            throw ActionError.failed(String(localized: "That drop type isn’t available. Try dragging its file from Finder."))
        }
        let folder = try ShelfLocations.importFolder(root: root)
        let name = Self.safeName(provider.suggestedName ?? "Attachment", extension: UTType(id)?.preferredFilenameExtension ?? "bin")
        let target = folder.appendingPathComponent(name)
        // Providers delete temporary representations after this callback returns.
        let output: URL = try await withCheckedThrowingContinuation { continuation in
            let gate = CallbackGate(continuation)
            provider.loadFileRepresentation(forTypeIdentifier: id) { source, error in
                guard let source else { gate.finish(.failure(error ?? ActionError.failed(String(localized: "Couldn’t receive that attachment.")))); return }
                do { try FileManager.default.copyItem(at: source, to: target); gate.finish(.success(target)) }
                catch { gate.finish(.failure(error)) }
            }
        }
        return [output]
    }

    private func data(from provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let gate = CallbackGate(continuation)
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let data { gate.finish(.success(data)) }
                else { gate.finish(.failure(error ?? ActionError.failed(String(localized: "The source app couldn’t provide that drop.")))) }
            }
        }
    }
    private func write(_ data: Data, name: String) throws -> URL {
        let folder = try ShelfLocations.importFolder(root: root)
        let url = folder.appendingPathComponent(Self.safeName(name))
        try data.write(to: url, options: .atomic)
        return url
    }
    nonisolated static func safeName(_ proposed: String, extension ext: String? = nil) -> String {
        var name = proposed.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == ".." { name = String(localized: "Dropped item") }
        name = String(name.prefix(160))
        if let ext, URL(fileURLWithPath: name).pathExtension.lowercased() != ext.lowercased() { name += "." + ext }
        return name
    }
}
