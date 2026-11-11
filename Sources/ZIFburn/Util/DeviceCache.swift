import Foundation

/// On-disk cache of minipro's device list, keyed by minipro version and by
/// which database was listed, so launch doesn't have to query minipro again.
/// Values are the `-q` database each chip came from ("" = minipro's default).
enum DeviceCache {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZIFburn/DeviceCache", isDirectory: true)
    }

    private static func url(key: String, version: String) -> URL {
        directory.appendingPathComponent("\(Sanitize.fileName(version))-\(Sanitize.fileName(key)).json")
    }

    static func load(key: String, version: String?) -> [String: String]? {
        guard let version, let data = try? Data(contentsOf: url(key: key, version: version)) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    static func save(_ devices: [String: String], key: String, version: String?) {
        guard let version, !devices.isEmpty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(devices) {
            try? data.write(to: url(key: key, version: version), options: .atomic)
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
