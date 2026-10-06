import AppKit
import Darwin
import WindowBehavior

/// Discovery and gesture ownership only. Clients apply geometry on their render
/// thread, so neither their layout graph nor per-frame AX writes cross this IPC.
final class SurfaceBridge {
    static let shared = SurfaceBridge()
    private let queue = DispatchQueue(label: "org.melty.windows.surfaces")
    private let lock = NSLock()
    private var claims = SurfaceClaims()
    private var enabled = false
    private var leftMove = false
    private var source: DispatchSourceRead?
    private let path: String

    init(path: String = NSHomeDirectory() + "/Library/Application Support/Melty Windows/surfaces-v1.sock") {
        self.path = path
    }

    func owns(window: UInt32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return claims.owns(window: window, now: ProcessInfo.processInfo.systemUptime)
    }

    func setEnabled(_ value: Bool, leftMove: Bool = true) {
        lock.lock(); enabled = value; self.leftMove = leftMove; lock.unlock()
        if source == nil { start() }
    }

    func owns(pid: Int32, window: UInt32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        // Keep the last agreement through its grace period even after pause.
        return claims.owns(pid: pid, window: window, now: ProcessInfo.processInfo.systemUptime)
    }

    private func start() {
        let directory = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory)
        } catch { Trace.write("surface bridge directory unavailable"); return }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            bytes.withUnsafeBytes { destination.copyBytes(from: $0) }
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        unlink(path) // The application's existing single-instance lock owns this endpoint.
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else { close(fd); return }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            self?.serve(client)
            close(client)
        }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }

    private func serve(_ fd: Int32) {
        _ = fcntl(fd, F_SETFL, 0)
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var uid: uid_t = 0, gid: gid_t = 0, pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid(),
              getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0 else { return }
        var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.1
        while !data.contains(10) && data.count < 4096 && ProcessInfo.processInfo.systemUptime < deadline {
            let n = read(fd, &buffer, 4096 - data.count)
            guard n > 0 else { return }
            data.append(contentsOf: buffer.prefix(n))
        }
        guard data.last == 10,
              let request = try? JSONDecoder().decode(Request.self, from: data),
              request.version == 1, request.operation == "claim", request.windows.count <= 128,
              Set(request.windows).count == request.windows.count else { return }
        let records = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let owned = Set(records.compactMap { record -> UInt32? in
            guard record[kCGWindowOwnerPID as String] as? Int32 == pid else { return nil }
            return record[kCGWindowNumber as String] as? UInt32
        })
        guard request.windows.allSatisfy({ owned.contains($0) }) else { return }
        lock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        let alreadyOwned = request.windows.allSatisfy { claims.owns(pid: pid, window: $0, now: now) }
        let buttonDown = [CGMouseButton.left, .right, .center].contains {
            CGEventSource.buttonState(.combinedSessionState, button: $0)
        }
        // New ownership starts between gestures. Never enable a layout solver
        // halfway through an outer-window drag that the utility already owns.
        let active = enabled && (alreadyOwned || !buttonDown)
        let moveEnabled = active && leftMove
        if active { claims.replace(pid: pid, windows: request.windows, now: now) }
        lock.unlock()
        var response: [String: Any] = ["version": 1, "capability": "native-edges", "enabled": active, "lease_seconds": 1]
        // A fresh path lets clients load this build without reopening their
        // windows. Already-open frame tokens retain their original helper.
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           let library = Bundle.main.privateFrameworksURL?.appendingPathComponent("SurfaceFrame-\(build)/MeltySurfaceFrame.dylib"),
           FileManager.default.fileExists(atPath: library.path) {
            response["frame_api"] = 1
            response["frame_library"] = library.path
            response["move_api"] = 1
            response["move_enabled"] = moveEnabled
        }
        guard var reply = try? JSONSerialization.data(withJSONObject: response) else { return }
        reply.append(10)
        reply.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            _ = write(fd, base, bytes.count)
        }
    }

    private struct Request: Decodable {
        let version: Int
        let operation: String
        let windows: [UInt32]
    }
}
