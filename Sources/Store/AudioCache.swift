import Foundation

/// Local copies of the narration files the Mac renders (audio/<paper id>/<page key>.m4a in the synced folder).
/// A small manifest per paper remembers which version of each page is cached, so edited papers get fresh audio.
enum AudioCache {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PaperDaily/audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func file(_ id: String, _ key: String) -> URL {
        directory.appendingPathComponent(id, isDirectory: true).appendingPathComponent("\(key).m4a")
    }

    private static func manifestURL(_ id: String) -> URL {
        directory.appendingPathComponent(id, isDirectory: true).appendingPathComponent("manifest.json")
    }

    static func manifest(_ id: String) -> [String: String] {
        guard let data = try? Data(contentsOf: manifestURL(id)) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    static func store(_ data: Data, id: String, key: String, fingerprint: String) {
        let url = file(id, key)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        var m = manifest(id)
        m[key] = fingerprint
        if let encoded = try? JSONEncoder().encode(m) { try? encoded.write(to: manifestURL(id), options: .atomic) }
    }

    static func has(_ id: String, _ key: String, fingerprint: String) -> Bool {
        manifest(id)[key] == fingerprint && FileManager.default.fileExists(atPath: file(id, key).path)
    }

    static func cachedFile(_ id: String, _ key: String) -> URL? {
        FileManager.default.fileExists(atPath: file(id, key).path) ? file(id, key) : nil
    }

    static func prune(keeping ids: Set<String>) {
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in existing where !ids.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
