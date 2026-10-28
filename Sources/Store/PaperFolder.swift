import Foundation
import Observation

/// Local copy of the synced folder, so papers work offline and survive cloud placeholders.
/// Files are stored byte for byte under their original names.
enum PaperCache {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PaperDaily/papers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func loadAll() -> [Paper] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().compactMap { name in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
            return try? JSONDecoder().decode(Paper.self, from: data)
        }
    }

    static func store(_ data: Data, as name: String) {
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    static func prune(keeping names: Set<String>) {
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in existing where name.hasSuffix(".json") && !names.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}

/// The folder (iCloud Drive, OneDrive, anything the Files app can show) that your Mac writes summaries into.
/// The user picks it once; we keep a security-scoped bookmark.
@Observable
final class PaperFolder {
    private(set) var folderName: String?
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    private(set) var message: String?
    private(set) var syncedCount = 0

    var isConfigured: Bool { folderName != nil }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let bookmarkKey = "papersFolderBookmark"
    @ObservationIgnored private var debugURL: URL?

    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-debugFolder"), i + 1 < args.count { debugURL = URL(fileURLWithPath: args[i + 1]) }
        #endif
        folderName = resolveURL()?.lastPathComponent
    }

    // MARK: Choosing the folder

    func setFolder(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            defaults.set(try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil), forKey: bookmarkKey)
            folderName = url.lastPathComponent
            message = nil
        } catch {
            message = "Could not remember this folder: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        defaults.removeObject(forKey: bookmarkKey)
        folderName = nil; message = nil; syncedCount = 0; lastSync = nil
    }

    private func resolveURL() -> URL? {
        if let debugURL { return debugURL }
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    // MARK: Sync

    struct Scan {
        var fileNames: [String] = []
        var datas: [String: Data] = [:]
        var errors: [String] = []
        var listed = false
    }

    /// Copies the folder's JSON files into the local cache. Returns true when the cache changed or was confirmed.
    @MainActor
    func sync() async -> Bool {
        guard let url = resolveURL(), !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }

        let scan = await Task.detached(priority: .utility) { Self.scan(url) }.value
        lastSync = .now
        guard scan.listed else {
            message = scan.errors.first ?? "Could not read the folder."
            return false
        }
        for (name, data) in scan.datas { PaperCache.store(data, as: name) }
        // Mirror deletions, but never drop a file that is still listed and only failed to read.
        PaperCache.prune(keeping: Set(scan.fileNames))
        AudioCache.prune(keeping: Set(scan.fileNames.map { String($0.dropLast(".json".count)) }))
        syncedCount = scan.datas.count
        message = scan.errors.isEmpty ? nil : scan.errors.joined(separator: "\n")
        return true
    }

    /// Reads the folder with file coordination, which also makes OneDrive / iCloud download cloud-only files.
    nonisolated private static func scan(_ url: URL) -> Scan {
        var result = Scan()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let coordinator = NSFileCoordinator()

        var listing: [String] = []
        var coordinationError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { dir in
            do { listing = try fm.contentsOfDirectory(atPath: dir.path); result.listed = true }
            catch { result.errors.append("Could not list the folder: \(error.localizedDescription)") }
        }
        if let coordinationError { result.errors.append(coordinationError.localizedDescription) }
        guard result.listed else { return result }

        // iCloud placeholders appear as ".name.json.icloud": ask for the real file.
        let names: [String] = listing.map { name in
            guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return name }
            let real = String(name.dropFirst().dropLast(".icloud".count))
            try? fm.startDownloadingUbiquitousItem(at: url.appendingPathComponent(real))
            return real
        }

        result.fileNames = names.filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
        for name in result.fileNames {
            let fileURL = url.appendingPathComponent(name)
            var data: Data?
            var readError: NSError?
            coordinator.coordinate(readingItemAt: fileURL, options: [], error: &readError) { u in
                for _ in 0..<20 {   // wait up to ~10 s for a placeholder to materialise
                    if let d = try? Data(contentsOf: u) { data = d; break }
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }
            guard let data else { result.errors.append("\(name): not downloaded yet"); continue }
            do { _ = try JSONDecoder().decode(Paper.self, from: data); result.datas[name] = data }
            catch { result.errors.append("\(name): \(describe(error))") }
        }

        return result
    }

    // MARK: Narration audio

    /// Local file with the Mac-rendered narration of one page, downloading it first if needed.
    /// Nil when the Mac has not rendered it (yet); the caller then falls back to the system voice.
    func audioFile(id: String, key: String) async -> URL? {
        guard let root = resolveURL() else { return nil }
        let remote = await Task.detached(priority: .userInitiated) { () -> [String: String]? in
            guard let data = Self.readCoordinated(root, "audio/\(id)/manifest.json") else { return nil }
            return (try? JSONDecoder().decode(AudioManifest.self, from: data))?.pages
        }.value
        // Offline or not rendered: use whatever copy we already have.
        guard let remote else { return AudioCache.cachedFile(id, key) }
        guard let fingerprint = remote[key] else { return nil }
        if AudioCache.has(id, key, fingerprint: fingerprint) { return AudioCache.file(id, key) }
        let data = await Task.detached(priority: .userInitiated) { Self.readCoordinated(root, "audio/\(id)/\(key).m4a") }.value
        guard let data else { return AudioCache.cachedFile(id, key) }
        AudioCache.store(data, id: id, key: key, fingerprint: fingerprint)
        return AudioCache.file(id, key)
    }

    private struct AudioManifest: Decodable { let pages: [String: String] }

    /// Coordinated read of one file below the folder; this also makes OneDrive / iCloud download cloud-only files.
    nonisolated private static func readCoordinated(_ root: URL, _ relativePath: String) -> Data? {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let url = root.appendingPathComponent(relativePath)
        let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
        guard fm.fileExists(atPath: url.path) || fm.fileExists(atPath: placeholder.path) else { return nil }
        try? fm.startDownloadingUbiquitousItem(at: url)
        var data: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { u in
            for _ in 0..<60 {   // up to ~30 s for a cloud-only file to arrive
                if let d = try? Data(contentsOf: u) { data = d; break }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        return data
    }

    nonisolated private static func describe(_ error: Error) -> String {
        if case DecodingError.keyNotFound(let key, _) = error { return "missing field “\(key.stringValue)”" }
        if case DecodingError.typeMismatch(_, let ctx) = error { return "wrong type at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))" }
        if case DecodingError.dataCorrupted = error { return "not valid JSON" }
        return error.localizedDescription
    }
}
