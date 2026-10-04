import Foundation

enum Trace {
    static let queue = DispatchQueue(label: "org.melty.windows.trace")
    static let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Melty Windows.log")
    static func write(_ message: String) {
        let line = String(format: "%.3f %@\n", Date().timeIntervalSince1970, message)
        queue.async {
            try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: path.path) { FileManager.default.createFile(atPath: path.path, contents: nil) }
            if let handle = try? FileHandle(forWritingTo: path) {
                defer { try? handle.close() }
                if let size = try? handle.seekToEnd(), size > 256_000 { try? handle.truncate(atOffset: 0); try? handle.seek(toOffset: 0) }
                try? handle.write(contentsOf: Data(line.utf8))
            }
        }
    }
}
