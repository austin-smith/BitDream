import Foundation
import TailscaleCore

protocol TailscaleDriving: Sendable {
    func perform(_ request: TailscaleNativeRequest) async throws -> TailscaleSnapshot
}

/// Blocking C/Go calls run on a dedicated serial queue, never a cooperative
/// executor or the main thread. The ABI owns no Swift callbacks or pointers.
final class TailscaleNativeDriver: TailscaleDriving {
    private let queue = DispatchQueue(label: "com.bitdream.tailscale", qos: .utility)

    func perform(_ request: TailscaleNativeRequest) async throws -> TailscaleSnapshot {
        let data = try JSONEncoder().encode(request)
        guard let input = String(data: data, encoding: .utf8) else { throw TailscaleError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let result = input.withCString { BDTailscaleCommand($0) }
                guard let result else {
                    continuation.resume(throwing: TailscaleError.unavailable)
                    return
                }
                defer { BDTailscaleFree(result) }
                do {
                    let snapshot = try JSONDecoder().decode(
                        TailscaleSnapshot.self, from: Data(String(cString: result).utf8)
                    )
                    guard snapshot.error == nil else { throw TailscaleError.unavailable }
                    continuation.resume(returning: snapshot)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

struct TailscaleStateDirectory: Sendable {
    var url: URL {
        get throws {
            var directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appending(path: "Tailscale", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: directory.path
            )
            #endif
            return directory
        }
    }
}
