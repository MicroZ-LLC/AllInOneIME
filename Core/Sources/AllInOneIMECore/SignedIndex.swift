import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A pack a signed index of the language library lists (`LanguagePackIndex.Entry`, `CodingPackIndex.Entry`): where its
/// file is (an https address, or a path relative to the library), its sha256 and its exact size in bytes.
protocol SignedIndexEntry {
    var url: String { get }
    var sha256: String { get }
    var size: Int64 { get }
}

extension LanguagePackIndex.Entry: SignedIndexEntry {}
extension CodingPackIndex.Entry: SignedIndexEntry {}

/// One of the language library's signed indexes (`packs.json`, `coding-packs.json`) and what both kinds of packs check
/// of it, in one place: it is what keeps out a pack someone else made. The index is fetched with its signature
/// (`<name>.sig`) and read only once the signature, by the key built into the app, holds for exactly its bytes, and its
/// schema is the one this app reads (`verify`); a pack's file is downloaded only from an allowed address, with a sha256
/// and a size to check it by (`fileURL`). What only one kind checks (a language pack's id, a coding pack's language and
/// size cap) is its library's.
struct SignedIndex<Index: Decodable>: Sendable {
    /// The index's file in the library.
    var name: String
    /// The schema this app reads.
    var schema: Int
    var baseURL: URL
    var configuration: URLSessionConfiguration
    /// Plain http to this computer (a test server): only for the developer commands and tests.
    var allowsLocalHTTP: Bool

    /// The index, fetched with its signature and verified (`verify`).
    func fetch(publicKey: Data) async throws -> Index {
        let index = try await get(name, limit: LanguagePackLibrary.maxIndexBytes)
        let signature: Data
        do {
            signature = try await get(name + ".sig", limit: 4096)
        } catch LanguagePackError.http(status: 404, _) {
            throw LanguagePackError.missingSignature
        }
        return try Self.verify(index, signature: signature, publicKey: publicKey, schema: schema)
    }

    /// The index in `data`, if `signature` is the key's signature of exactly these bytes (checked first) and it is of
    /// `schema`.
    static func verify(_ data: Data, signature: Data, publicKey: Data, schema: Int) throws -> Index {
        do {
            try PluginLibrary.checkSignature(data, signature: signature, publicKey: publicKey)
        } catch let error as PluginLibraryError {
            throw LanguagePackError(error)
        }
        guard let found = try? JSONDecoder().decode(IndexSchema.self, from: data).schema else { throw LanguagePackError.malformedIndex }
        guard found == schema else { throw LanguagePackError.unsupportedSchema(found) }
        guard let index = try? JSONDecoder().decode(Index.self, from: data) else { throw LanguagePackError.malformedIndex }
        return index
    }

    /// Where `entry`'s file is, once what the index says of it holds up, before anything is downloaded: a sha256 of 64
    /// hex digits, a size above 0 (and at most `maxSize`), an allowed address (`isAllowed`). `invalidEntry` naming what
    /// doesn't.
    func fileURL(of entry: some SignedIndexEntry, maxSize: Int64 = .max) throws -> URL {
        guard entry.sha256.count == 64, entry.sha256.allSatisfy(\.isHexDigit) else { throw LanguagePackError.invalidEntry("sha256") }
        guard entry.size > 0, entry.size <= maxSize else { throw LanguagePackError.invalidEntry("size") }
        guard let url = URL(string: entry.url, relativeTo: baseURL)?.absoluteURL, isAllowed(url) else {
            throw LanguagePackError.invalidEntry(entry.url)
        }
        return url
    }

    /// https anywhere (the signed hash, not the host, vouches for the bytes); http only to this computer, when allowed.
    func isAllowed(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http": return allowsLocalHTTP && LanguagePackLibrary.isLocal(url)
        default: return false
        }
    }

    /// Just an index's schema, read before the rest.
    private struct IndexSchema: Decodable { var schema: Int }

    private func get(_ path: String, limit: Int) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        guard isAllowed(url) else { throw LanguagePackError.unreachable(url.absoluteString) }
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw LanguagePackError.unreachable(url.host ?? url.absoluteString)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw LanguagePackError.http(status: status, file: path) }
        guard data.count <= limit else { throw LanguagePackError.tooLarge(path) }
        return data
    }
}
