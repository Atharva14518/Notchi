import Foundation

/// Removes complete ancillary metadata chunks from our ImageIO-generated PNG.
/// IDAT bytes and their CRCs are copied unchanged; color-management chunks remain.
enum PNGMetadataStripper {
    private static let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
    private static let metadataChunks: Set<String> = ["eXIf", "tEXt", "zTXt", "iTXt", "tIME"]

    static func strip(at url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".metadata-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let total = try input.seekToEnd()
        try input.seek(toOffset: 0)
        guard try readExactly(8, from: input) == signature else { throw invalidPNG() }
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else {
            throw ActionError.failed(String(localized: "Couldn’t prepare a metadata-free image."))
        }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        try output.write(contentsOf: signature)
        var offset: UInt64 = 8
        var ended = false
        var first = true
        while offset < total {
            guard total - offset >= 12 else { throw invalidPNG() }
            let header = try readExactly(8, from: input)
            let length = header.prefix(4).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            guard length <= total - offset - 12,
                  let type = String(data: header.suffix(4), encoding: .ascii) else { throw invalidPNG() }
            if first && (type != "IHDR" || length != 13) { throw invalidPNG() }
            first = false
            let keep = !metadataChunks.contains(type)
            if keep { try output.write(contentsOf: header) }
            // Stream payload plus CRC in bounded blocks, including chunks we discard.
            var remaining = length + 4
            while remaining > 0 {
                let count = Int(min(remaining, 64 * 1024))
                let block = try readExactly(count, from: input)
                if keep { try output.write(contentsOf: block) }
                remaining -= UInt64(count)
            }
            offset += length + 12
            if type == "IEND" {
                guard length == 0, offset == total else { throw invalidPNG() }
                ended = true
                break
            }
        }
        guard ended else { throw invalidPNG() }
        try output.synchronize()
        try output.close()
        try input.close()
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary, options: .usingNewMetadataOnly)
    }

    private static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let bytes = try handle.read(upToCount: count - result.count), !bytes.isEmpty else { throw invalidPNG() }
            result.append(bytes)
        }
        return result
    }
    private static func invalidPNG() -> ActionError {
        .failed(String(localized: "The PNG export was incomplete. Your original is unchanged; please retry."))
    }
}
